open Import

let parse_js source = Jsoo.Parse_js.(parse (lexer_from_string source))

let rev_prop accessor name value =
  let past = accessor () in
  if past = value
  then fun () -> ()
  else if value
  then (
    Jsoo.Config.Flag.enable name;
    fun () -> Jsoo.Config.Flag.disable name)
  else (
    Jsoo.Config.Flag.disable name;
    fun () -> Jsoo.Config.Flag.enable name)

let rec call_all = function
  | [] -> ()
  | f :: rest ->
      f ();
      call_all rest

let print_compiled_js ?(pretty = true) cmo_channel =
  let program, _, debug_data, _ =
    Jsoo.Parse_bytecode.from_channel ~debug:`Names cmo_channel
  in
  let buffer = Buffer.create 100 in
  let pp = Jsoo.Pretty_print.to_buffer buffer in
  let silence_compiler () =
    let prev = !Jsoo.Stdlib.quiet in
    Jsoo.Stdlib.quiet := true;
    fun () -> Jsoo.Stdlib.quiet := prev
  in
  let props =
    if pretty
    then
      Jsoo.Config.Flag.
        [ rev_prop genprim "genprim" false
        ; rev_prop shortvar "shortvar" false
        ; rev_prop share_constant "share" false
        ; rev_prop excwrap "excwrap" false
        ; rev_prop pretty "pretty" true
        ; silence_compiler () ]
    else
      Jsoo.Config.Flag.
        [ rev_prop genprim "genprim" true
        ; rev_prop shortvar "shortvar" true
        ; rev_prop share_constant "share" true
        ; rev_prop excwrap "excwrap" true
        ; rev_prop pretty "pretty" false
        ; silence_compiler () ]
  in
  (try Jsoo.Driver.f pp debug_data program
   with e ->
     call_all props;
     raise e);
  Buffer.contents buffer

let compile_ocaml_to_bytecode source =
  let temp_file = Filename.temp_file "jsoo_test" ".ml" in
  let out = open_out temp_file in
  Printf.fprintf out "%s" source;
  close_out out;
  let proc =
    Unix.open_process
      (Format.sprintf "ocamlfind ocamlc -g %s -I Stdlib -o %s.cmo" temp_file temp_file)
  in
  (match Unix.close_process proc with
  | WEXITED 0 -> ()
  | WEXITED n -> failwith (Format.sprintf "exited %d" n)
  | WSIGNALED n -> failwith (Format.sprintf "signaled %d" n)
  | WSTOPPED n -> failwith (Format.sprintf "stopped %d" n));
  open_in (Format.sprintf "%s.cmo" temp_file)

type find_result =
  { expressions : J.expression list
  ; statements : J.statement list
  ; var_decls : J.variable_declaration list }

type finder_fun =
  { expression : J.expression -> unit
  ; statement : J.statement -> unit
  ; variable_decl : J.variable_declaration -> unit }

class finder ff =
  object
    inherit Jsoo.Js_traverse.map as super

    method! variable_declaration v =
      ff.variable_decl v;
      super#variable_declaration v

    method! expression x =
      ff.expression x;
      super#expression x

    method! statement s =
      ff.statement s;
      super#statement s
  end

let find_javascript
    ?(expression = fun _ -> false)
    ?(statement = fun _ -> false)
    ?(var_decl = fun _ -> false)
    program =
  let expressions, statements, var_decls = ref [], ref [], ref [] in
  let append r v = r := v :: !r in
  let expression a = if expression a then append expressions a in
  let statement a = if statement a then append statements a in
  let variable_decl a = if var_decl a then append var_decls a in
  let t = {expression; statement; variable_decl} in
  let trav = new finder t in
  ignore (trav#program program);
  {statements = !statements; expressions = !expressions; var_decls = !var_decls}

let expression_to_string ?(compact = false) e =
  let e = [J.Statement (J.Expression_statement e), J.N] in
  let buffer = Buffer.create 17 in
  let pp = Jsoo.Pretty_print.to_buffer buffer in
  Jsoo.Pretty_print.set_compact pp compact;
  Jsoo.Js_output.program pp e;
  Buffer.contents buffer
