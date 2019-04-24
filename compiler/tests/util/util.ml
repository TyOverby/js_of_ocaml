(* Js_of_ocaml tests
 * http://www.ocsigen.org/js_of_ocaml/
 * Copyright (C) 2019 Ty Overby
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
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
module Jsoo = Js_of_ocaml_compiler

module Format : Format_intf.S = struct
  type ocaml_text = string

  type js_text = string

  type sourcemap_text = string

  type ocaml_file = string

  type sourcemap_file = string

  type js_file = string

  type cmo_file = string

  type bc_file = string

  let read_file file =
    let ic = open_in_bin file in
    let n = in_channel_length ic in
    let s = Bytes.create n in
    really_input ic s 0 n;
    close_in ic;
    Bytes.unsafe_to_string s

  let write_file ~suffix contents =
    let temp_file = Filename.temp_file "jsoo_test" suffix in
    let channel = open_out temp_file in
    Printf.fprintf channel "%s" contents;
    close_out channel;
    temp_file

  let read_js = read_file

  let read_map = read_file

  let read_ocaml = read_file

  let write_js = write_file ~suffix:".js"

  let write_ocaml = write_file ~suffix:".ml"

  let id x = x

  let js_text_of_string = id

  let ocaml_text_of_string = id

  let string_of_js_text = id

  let string_of_map_text = id

  let string_of_ocaml_text = id

  let path_of_ocaml_file = id

  let path_of_js_file = id

  let path_of_map_file = id

  let path_of_cmo_file = id

  let path_of_bc_file = id

  let ocaml_file_of_path = id

  let js_file_of_path = id

  let map_file_of_path = id

  let cmo_file_of_path = id

  let bc_file_of_path = id
end

let parse_js file =
  file
  |> Format.read_js
  |> Format.string_of_js_text
  |> Jsoo.Parse_js.lexer_from_string
  |> Jsoo.Parse_js.parse

let channel_to_string c_in =
  let good_round_number = 1024 in
  let buffer = Buffer.create good_round_number in
  let rec loop () =
    Buffer.add_channel buffer c_in good_round_number;
    loop ()
  in
  (try loop () with End_of_file -> ());
  Buffer.contents buffer

let exec_to_string_exn ~env ~cmd =
  let env = Array.concat [Unix.environment (); Array.of_list env] in
  let proc_result_ok std_out =
    let open Unix in
    function
    | WEXITED 0 -> std_out
    | WEXITED i ->
        print_endline std_out;
        failwith (Stdlib.Format.sprintf "process exited with error code %d\n %s" i cmd)
    | WSIGNALED i ->
        print_endline std_out;
        failwith
          (Stdlib.Format.sprintf "process signaled with signal number %d\n %s" i cmd)
    | WSTOPPED i ->
        print_endline std_out;
        failwith
          (Stdlib.Format.sprintf "process stopped with signal number %d\n %s" i cmd)
  in
  let ((proc_in, _, _) as proc_full) = Unix.open_process_full cmd env in
  let results = channel_to_string proc_in in
  proc_result_ok results (Unix.close_process_full proc_full)

let get_project_build_directory () =
  let regex_text = "_build/default" in
  let regex = Str.regexp regex_text in
  let left = Sys.getcwd () |> Str.split regex |> List.hd in
  Filename.concat left regex_text

let run_javascript file =
  exec_to_string_exn
    ~env:[]
    ~cmd:(Stdlib.Format.sprintf "node %s" (Format.path_of_js_file file))

let swap_extention filename ~ext =
  Stdlib.Format.sprintf "%s.%s" (Filename.remove_extension filename) ext

let compile_to_javascript ~pretty ~sourcemap file =
  let file_no_ext = Filename.chop_extension file in
  let out_file = swap_extention file ~ext:"js" in
  let extra_args =
    List.flatten
      [ (if pretty then ["--pretty"] else [])
      ; (if sourcemap then ["--sourcemap"] else [])
      ; ["--no-runtime"]
      ; [Filename.concat (get_project_build_directory ()) "runtime/runtime.js"] ]
  in
  let extra_args = String.concat " " extra_args in
  let cmd =
    Stdlib.Format.sprintf "../js_of_ocaml.exe %s %s -o %s" extra_args file out_file
  in
  let env =
    [Stdlib.Format.sprintf "BUILD_PATH_PREFIX_MAP=/root/jsoo_test=%s" file_no_ext]
  in
  let stdout = exec_to_string_exn ~env ~cmd in
  print_string stdout;
  (* this print shouldn't do anything, so if
     something weird happens, we'll get the results here *)
  let sourcemap_file = swap_extention file ~ext:"map" |> Format.map_file_of_path in
  Format.js_file_of_path out_file, if sourcemap then Some sourcemap_file else None

let compile_bc_to_javascript ?(pretty = true) ?(sourcemap = true) file =
  Format.path_of_bc_file file |> compile_to_javascript ~pretty ~sourcemap

let compile_cmo_to_javascript ?(pretty = true) ?(sourcemap = true) file =
  Format.path_of_cmo_file file |> compile_to_javascript ~pretty ~sourcemap

let compile_ocaml_to_cmo file =
  let file = Format.path_of_ocaml_file file in
  let out_file = swap_extention file ~ext:"cmo" in
  let _ =
    exec_to_string_exn
      ~env:[]
      ~cmd:(Stdlib.Format.sprintf "ocamlc -c -g %s -o %s" file out_file)
  in
  Format.cmo_file_of_path out_file

let compile_ocaml_to_bc file =
  let file = Format.path_of_ocaml_file file in
  let out_file = swap_extention file ~ext:"bc" in
  let _ =
    exec_to_string_exn
      ~env:[]
      ~cmd:(Stdlib.Format.sprintf "ocamlc -g unix.cma %s -o %s" file out_file)
  in
  Format.bc_file_of_path out_file

let program_to_string ?(compact = false) p =
  let buffer = Buffer.create 17 in
  let pp = Jsoo.Pretty_print.to_buffer buffer in
  Jsoo.Pretty_print.set_compact pp compact;
  Jsoo.Js_output.program pp p;
  Buffer.contents buffer

let expression_to_string ?(compact = false) e =
  let module J = Jsoo.Javascript in
  let p = [J.Statement (J.Expression_statement e), J.N] in
  program_to_string ~compact p

class find_variable_declaration r n = object
  inherit Jsoo.Js_traverse.map as super
  method! variable_declaration v =
    (match v with
     | Jsoo.Javascript.S {name; _}, _ when name = n ->
        r := v :: !r
     | _ -> ());
    super#variable_declaration v
end

let print_var_decl program n =
  let r = ref [] in
  let o = new find_variable_declaration r n in
  ignore(o#program program);
  print_string (Stdlib.Format.sprintf "var %s = " n);
  match !r with
  | [(_, Some (expression, _))] -> print_string (expression_to_string expression)
  | _ -> print_endline "not found"


class find_function_declaration r n = object
  inherit Jsoo.Js_traverse.map as super
  method! source s =
    (match s with
     | Function_declaration (Jsoo.Javascript.S {name; _}, _, _, _ as fd) when name = n ->
        r:=fd::!r
     | Function_declaration _
     | Statement _ -> ());
    super#source s
end

let print_fun_decl program n =
  let r = ref [] in
  let o = new find_function_declaration r n in
  ignore(o#program program);
  let module J = Jsoo.Javascript in
  match !r with
  | [fd] -> print_string (program_to_string [J.Function_declaration fd, J.N])
  | _ -> print_endline "not found"

let compile_and_run s =
  s
  |> Format.ocaml_text_of_string
  |> Format.write_ocaml
  |> compile_ocaml_to_bc
  |> compile_bc_to_javascript
  |> Stdlib.fst
  |> run_javascript
  |> print_endline
