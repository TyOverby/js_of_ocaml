(* Js_of_ocaml compiler
 * http://www.ocsigen.org/js_of_ocaml/
 * Copyright (C) 2010 Jérôme Vouillon
 * Laboratoire PPS - CNRS Université Paris Diderot
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, with linking exception;
 * either version 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
 *)
open Stdlib

let debug = Debug.find "main"

let times = Debug.find "times"

let tailcall p =
  if debug () then Format.eprintf "Tail-call optimization...@.";
  Tailcall.f p

let deadcode' p =
  if debug () then Format.eprintf "Dead-code...@.";
  Deadcode.f p

let deadcode p =
  let r, _ = deadcode' p in
  r

let inline p =
  if Config.Flag.inline () && Config.Flag.deadcode ()
  then (
    let p, live_vars = deadcode' p in
    if debug () then Format.eprintf "Inlining...@.";
    Inline.f p live_vars)
  else p

let specialize_1 (p, info) =
  if debug () then Format.eprintf "Specialize...@.";
  Specialize.f info p

let specialize_js (p, info) =
  if debug () then Format.eprintf "Specialize js...@.";
  Specialize_js.f info p

let specialize' (p, info) =
  let p = specialize_1 (p, info) in
  let p = specialize_js (p, info) in
  p, info

let specialize p = fst (specialize' p)

let eval (p, info) = if Config.Flag.staticeval () then Eval.f info p else p

let flow p =
  if debug () then Format.eprintf "Data flow...@.";
  Flow.f p

let flow_simple p =
  if debug () then Format.eprintf "Data flow...@.";
  Flow.f ~skip_param:true p

let phi p =
  if debug () then Format.eprintf "Variable passing simplification...@.";
  Phisimpl.f p

let print p =
  if debug () then Code.print_program (fun _ _ -> "") p;
  p

let ( >> ) f g x = g (f x)

let rec loop max name round i (p : 'a) : 'a =
  let p' = round p in
  if i >= max || Code.eq p' p
  then p'
  else (
    if times () then Format.eprintf "Start Iteration (%s) %d...@." name i;
    loop max name round (i + 1) p')

let identity x = x

(* o1 *)

let o1 : 'a -> 'a =
  print
  >> tailcall
  >> flow_simple
  >> (* flow simple to keep information for furture tailcall opt *)
     specialize'
  >> eval
  >> inline
  >> (* inlining may reveal new tailcall opt *)
     deadcode
  >> tailcall
  >> phi
  >> flow
  >> specialize'
  >> eval
  >> inline
  >> deadcode
  >> print
  >> flow
  >> specialize'
  >> eval
  >> inline
  >> deadcode
  >> phi
  >> flow
  >> specialize
  >> identity

(* o2 *)

let o2 : 'a -> 'a = loop 10 "o1" o1 1 >> print

(* o3 *)

let round1 : 'a -> 'a =
  print
  >> tailcall
  >> inline
  >> (* inlining may reveal new tailcall opt *)
     deadcode
  >> (* deadcode required before flow simple -> provided by constant *)
     flow_simple
  >> (* flow simple to keep information for furture tailcall opt *)
     specialize'
  >> eval
  >> identity

let round2 = flow >> specialize' >> eval >> deadcode >> o1

let o3 = loop 10 "tailcall+inline" round1 1 >> loop 10 "flow" round2 1 >> print

let generate d ~exported_runtime (p, live_vars) =
  if times () then Format.eprintf "Start Generation...@.";
  Generate.f p ~exported_runtime live_vars d

let header formatter ~custom_header =
  (match custom_header with
  | None -> ()
  | Some c -> Pretty_print.string formatter (c ^ "\n"));
  let version =
    match Compiler_version.git_version with
    | "" -> Compiler_version.s
    | v -> Printf.sprintf "%s+git-%s" Compiler_version.s v
  in
  Pretty_print.string formatter ("// Generated by js_of_ocaml " ^ version ^ "\n")

let debug_linker = Debug.find "linker"

let global_object = Constant.global_object

let extra_js_files =
  lazy
    (List.fold_left Constant.extra_js_files ~init:[] ~f:(fun acc file ->
         try
           let ss =
             List.fold_left
               (Linker.parse_file file)
               ~init:StringSet.empty
               ~f:(fun ss {Linker.provides; _} ->
                 match provides with
                 | Some (_, name, _, _) -> StringSet.add name ss
                 | _ -> ss)
           in
           (file, ss) :: acc
         with _ -> acc))

let report_missing_primitives missing =
  let missing =
    List.fold_left
      (Lazy.force extra_js_files)
      ~init:missing
      ~f:(fun missing (file, pro) ->
        let d = StringSet.inter missing pro in
        if not (StringSet.is_empty d)
        then (
          warn "Missing primitives provided by %s:@." file;
          StringSet.iter (fun nm -> warn "  %s@." nm) d;
          StringSet.diff missing pro)
        else missing)
  in
  if not (StringSet.is_empty missing)
  then (
    warn "Missing primitives:@.";
    StringSet.iter (fun nm -> warn "  %s@." nm) missing)

let gen_missing js missing =
  let open Javascript in
  let miss =
    StringSet.fold
      (fun prim acc ->
        let p = S {name = prim; var = None} in
        ( p
        , Some
            ( ECond
                ( EBin
                    ( NotEqEq
                    , EDot (EVar (S {name = global_object; var = None}), prim)
                    , EVar (S {name = "undefined"; var = None}) )
                , EDot (EVar (S {name = global_object; var = None}), prim)
                , EFun
                    ( None
                    , []
                    , [ ( Statement
                            (Expression_statement
                               (ECall
                                  ( EVar (S {name = "caml_failwith"; var = None})
                                  , [ EBin
                                        ( Plus
                                        , EStr (prim, `Utf8)
                                        , EStr (" not implemented", `Utf8) ) ]
                                  , N )))
                        , N ) ]
                    , N ) )
            , N ) )
        :: acc)
      missing
      []
  in
  if not (StringSet.is_empty missing)
  then (
    warn "There are some missing primitives@.";
    warn "Dummy implementations (raising 'Failure' exception) ";
    warn "will be used if they are not available at runtime.@.";
    warn "You can prevent the generation of dummy implementations with ";
    warn "the commandline option '--disable genprim'@.";
    report_missing_primitives missing);
  (Statement (Variable_statement miss), N) :: js

let link ~standalone ~linkall ~export_runtime (js : Javascript.source_elements) :
    Linker.output =
  if not standalone
  then {runtime_code = js; always_required_codes = []}
  else
    let t = Timer.make () in
    if times () then Format.eprintf "Start Linking...@.";
    let traverse = new Js_traverse.free in
    let js = traverse#program js in
    let free = traverse#get_free_name in
    let prim = Primitive.get_external () in
    let prov = Linker.get_provided () in
    let all_external = StringSet.union prim prov in
    let used = StringSet.inter free all_external in
    let linkinfos = Linker.init () in
    let linkinfos, missing = Linker.resolve_deps ~linkall linkinfos used in
    (* gen_missing may use caml_failwith *)
    let linkinfos, missing =
      if (not (StringSet.is_empty missing)) && Config.Flag.genprim ()
      then
        let linkinfos, missing2 =
          Linker.resolve_deps linkinfos (StringSet.singleton "caml_failwith")
        in
        linkinfos, StringSet.union missing missing2
      else linkinfos, missing
    in
    let js = if Config.Flag.genprim () then gen_missing js missing else js in
    if times () then Format.eprintf "  linking: %a@." Timer.print t;
    let js =
      if export_runtime
      then
        let open Javascript in
        let all = Linker.all linkinfos in
        let all = List.map all ~f:(fun name -> PNI name, EVar (S {name; var = None})) in
        ( Statement
            (Expression_statement
               (EBin
                  ( Eq
                  , EDot (EVar (S {name = global_object; var = None}), "jsoo_runtime")
                  , EObj all )))
        , N )
        :: js
      else js
    in
    Linker.link js linkinfos

let field i = Format.sprintf "f%d" i

class macro =
  object (m)
    inherit Js_traverse.map as super

    method expression x =
      let module J = Javascript in
      match x with
      | J.ECall (J.EVar (J.S {J.name = "BLOCK"; _}), tag :: args, _) ->
          let length = J.ENum (float_of_int (List.length args)) in
          let one str e = J.PNI str, m#expression e in
          let apply_one i e = one (field i) e in
          J.EObj (one "tag" tag :: one "length" length :: List.mapi args ~f:apply_one)
      | J.ECall (J.EVar (J.S {J.name = "TAG"; _}), [e], _) ->
          J.EDot (m#expression e, "tag")
      | J.ECall (J.EVar (J.S {J.name = "LENGTH"; _}), [e], _) ->
          J.EDot (m#expression e, "length")
      | J.ECall (J.EVar (J.S {J.name = "FIELD"; _}), [e; J.ENum i], _) ->
          J.EDot (m#expression e, field (int_of_float i))
      | J.ECall (J.EVar (J.S {J.name = "FIELD"; _}), [e; i], _) ->
          J.EAccess (m#expression e, J.EBin (J.Plus, J.EStr ("f", `Utf8), m#expression i))
      | J.ECall (J.EVar (J.S {J.name = "ISBLOCK"; _}), [e], _) ->
          J.EBin
            ( J.EqEq
            , J.EUn (J.Typeof, J.EDot (m#expression e, "tag"))
            , J.EStr ("number", `Utf8) )
      | J.ECall
          ( J.EVar (J.S {J.name = "BLOCK" | "FIELD" | "TAG" | "LENGTH" | "ISBLOCK"; _})
          , _
          , _ ) ->
          assert false
      | e -> super#expression e
  end

let macro js =
  let trav = new macro in
  trav#program js

let check_js js =
  let t = Timer.make () in
  if times () then Format.eprintf "Start Checks...@.";
  let traverse = new Js_traverse.free in
  let js = traverse#program js in
  let free = traverse#get_free_name in
  let prim = Primitive.get_external () in
  let prov = Linker.get_provided () in
  let all_external = StringSet.union prim prov in
  let missing = StringSet.inter free all_external in
  let missing = StringSet.diff missing Reserved.provided in
  let other = StringSet.diff free missing in
  let res = VarPrinter.get_reserved () in
  let other = StringSet.diff other res in
  if not (StringSet.is_empty missing) then report_missing_primitives missing;
  let probably_prov = StringSet.inter other Reserved.provided in
  let other = StringSet.diff other probably_prov in
  if (not (StringSet.is_empty other)) && debug_linker ()
  then (
    warn "Missing variables:@.";
    StringSet.iter (fun nm -> warn "  %s@." nm) other);
  if (not (StringSet.is_empty probably_prov)) && debug_linker ()
  then (
    warn "Variables provided by the browser:@.";
    StringSet.iter (fun nm -> warn "  %s@." nm) probably_prov);
  if times () then Format.eprintf "  checks: %a@." Timer.print t;
  js

let coloring js =
  let t = Timer.make () in
  if times () then Format.eprintf "Start Coloring...@.";
  let traverse = new Js_traverse.free in
  let js = traverse#program js in
  let free = traverse#get_free_name in
  VarPrinter.add_reserved (StringSet.elements free);
  let js = Js_assign.program js in
  if times () then Format.eprintf "  coloring: %a@." Timer.print t;
  js

let output formatter ~standalone ~custom_header ?source_map () js =
  let t = Timer.make () in
  if times () then Format.eprintf "Start Writing file...@.";
  if standalone then header ~custom_header formatter;
  Js_output.program formatter ?source_map js;
  if times () then Format.eprintf "  write: %a@." Timer.print t

let pack ~global {Linker.runtime_code = js; always_required_codes} =
  let module J = Javascript in
  let t = Timer.make () in
  if times () then Format.eprintf "Start Flagizing js...@.";
  (* pre pack optim *)
  let js =
    if Config.Flag.share_constant ()
    then (
      let t1 = Timer.make () in
      let js = (new Js_traverse.share_constant)#program js in
      if times () then Format.eprintf "    share constant: %a@." Timer.print t1;
      js)
    else js
  in
  let js =
    if Config.Flag.compact_vardecl ()
    then (
      let t2 = Timer.make () in
      let js = (new Js_traverse.compact_vardecl)#program js in
      if times () then Format.eprintf "    compact var decl: %a@." Timer.print t2;
      js)
    else js
  in
  (* pack *)
  let use_strict js ~can_use_strict =
    if Config.Flag.strictmode () && can_use_strict
    then (J.Statement (J.Expression_statement (J.EStr ("use strict", `Utf8))), J.N) :: js
    else js
  in
  let wrap_in_iifa ~can_use_strict js =
    let f =
      J.EFun
        ( None
        , [J.S {J.name = global_object; var = None}]
        , use_strict js ~can_use_strict
        , J.U )
    in
    let expr =
      match global with
      | `Function -> f
      | `Bind_to _ -> f
      | `Custom name -> J.ECall (f, [J.EVar (J.S {J.name; var = None})], J.N)
      | `Auto ->
          let global =
            J.ECall
              ( J.EFun
                  ( None
                  , []
                  , [ ( J.Statement
                          (J.Return_statement
                             (Some (J.EVar (J.S {J.name = "this"; var = None}))))
                      , J.N ) ]
                  , J.N )
              , []
              , J.N )
          in
          J.ECall (f, [global], J.N)
    in
    match global with
    | `Bind_to name ->
        [ ( J.Statement
              (J.Variable_statement [J.S {J.name; var = None}, Some (expr, J.N)])
          , J.N ) ]
    | _ -> [J.Statement (J.Expression_statement expr), J.N]
  in
  let always_required_js =
    (* CR-someday hheuzard: consider adding a comments in the generated file with original
       location. e.g.
       {v
          //# 1 polyfill/classlist.js
       v}
    *)
    List.map always_required_codes ~f:(fun {Linker.program; filename = _} ->
        wrap_in_iifa ~can_use_strict:false program)
  in
  let runtime_js = wrap_in_iifa ~can_use_strict:true js in
  let js = List.flatten always_required_js @ runtime_js in
  (* post pack optim *)
  let t3 = Timer.make () in
  let js = (new Js_traverse.simpl)#program js in
  if times () then Format.eprintf "    simpl: %a@." Timer.print t3;
  let t4 = Timer.make () in
  let js = (new Js_traverse.clean)#program js in
  if times () then Format.eprintf "    clean: %a@." Timer.print t4;
  let js =
    if Config.Flag.shortvar ()
    then (
      let t5 = Timer.make () in
      let keep = StringSet.empty in
      let js = (new Js_traverse.rename_variable keep)#program js in
      if times () then Format.eprintf "    shortten vars: %a@." Timer.print t5;
      js)
    else js
  in
  if times () then Format.eprintf "  optimizing: %a@." Timer.print t;
  js

let configure formatter p =
  let pretty = Config.Flag.pretty () in
  Pretty_print.set_compact formatter (not pretty);
  Code.Var.set_pretty (pretty && not (Config.Flag.shortvar ()));
  Code.Var.set_stable (Config.Flag.stable_var ());
  p

type profile = Code.program -> Code.program

let f
    ?(standalone = true)
    ?(global = `Auto)
    ?(profile = o1)
    ?(dynlink = false)
    ?(linkall = false)
    ?source_map
    ?custom_header
    formatter
    d =
  let exported_runtime = not standalone in
  let linkall = linkall || dynlink in
  configure formatter
  >> profile
  >> Generate_closure.f
  >> deadcode'
  >> generate d ~exported_runtime
  >> link ~standalone ~linkall ~export_runtime:dynlink
  >> pack ~global
  >> macro
  >> coloring
  >> check_js
  >> output formatter ~standalone ~custom_header ?source_map ()

let from_string prims s formatter =
  let p, d = Parse_bytecode.from_string prims s in
  f ~standalone:false ~global:`Function formatter d p

let profiles = [1, o1; 2, o2; 3, o3]

let profile i = try Some (List.assoc i profiles) with Not_found -> None

module For_testing = struct
  let macro = macro
end
