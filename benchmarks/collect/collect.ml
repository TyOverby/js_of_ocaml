type t =
  | File of {path: string; name: string}
  | Directory of {path: string; name : string; children : t list}

let rec tree name path =
  let children =
    Sys.readdir path
    |> Array.to_list
    |> List.map (fun name ->
           let path = Filename.concat path name in
           if Sys.is_directory path then tree name path else File {name; path})
  in
  Directory {name; path; children}

let print t =
  let rec print_h cur_depth t =
    let spaces = String.init cur_depth (fun _ -> ' ') in
    match t with
    | File {name; _} ->
        print_string spaces;
        print_endline name
    | Directory {name; children; _} ->
        print_string spaces;
        print_string name;
        print_endline "/";
        List.iter (print_h (cur_depth + 4)) children
  in
  print_h 0 t

type test = {
  name : string;
  categories: (string * float list) list
}

let read_lines file =
  let lines = ref [] in
  let rec read_line () =
    let line = input_line file in
    lines := line :: !lines;
    read_line ()
  in
  (try read_line ()
   with End_of_file ->  ());
  !lines

module String_map = Map.Make(String)

let rec collect acc =
  function
  | File {path; name} ->
    let values =
      read_lines (open_in path)
      |> List.map float_of_string_opt
      |> List.map (function Some a -> [a] | None -> [])
      |> List.flatten
    in
    String_map.update name (function
      | None -> Some { name; categories = [path, values] }
      | Some existing -> Some {existing with categories = (path, values) :: existing.categories})
    acc
  | Directory {children; _} ->
    List.fold_left collect acc children
;;

let gathered = collect String_map.empty (tree "./" "./");;

let rec print_array newline f = function
  | [] -> ()
  | [a] -> f a
  | a :: b :: xs ->
    f a;
    print_char ',';
    if newline then print_char '\n';
    print_array newline f (b :: xs)
in

print_char '{';
print_array true (fun (_, {name; categories}) ->
  let print_category (name, values) =
    print_char '"';
    print_string name;
    print_char '"';
    print_char '=';
    print_char '[';
    print_array false print_float values;
    print_char ']';
  in

  print_char '"';
  print_string name;
  print_char '"';
  print_char '=';
  print_char '{';
  print_array true print_category categories;
  print_char '}';
  ()
) (String_map.bindings gathered );
print_char '}';
