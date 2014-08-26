// Js_of_ocaml toplevel runtime support
// http://www.ocsigen.org/js_of_ocaml/
// Copyright (C) 2011 Jérôme Vouillon
// Laboratoire PPS - CNRS Université Paris Diderot
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU Lesser General Public License as published by
// the Free Software Foundation, with linking exception;
// either version 2.1 of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Lesser General Public License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

//Provides: caml_terminfo_setup
function caml_terminfo_setup () { return 1; } // Bad_term
//Provides: caml_terminfo_backup
function caml_terminfo_backup () { return 0; }
//Provides: caml_terminfo_standout
function caml_terminfo_standout () { return 0; }
//Provides: caml_terminfo_resume
function caml_terminfo_resume () { return 0; }
//Provides: caml_invoke_traced_function
//Requires: caml_invalid_argument
function caml_invoke_traced_function() {
  caml_invalid_argument("Meta.invoke_traced_function");
}
//Provides: caml_get_current_environment
//Requires: caml_failwith
function caml_get_current_environment() {
  caml_failwith("caml_get_current_environment not Implemented");
}
//////////////////////////////////////////////////////////////////////

//Provides: caml_get_section_table
//Requires: caml_global_data
function caml_get_section_table () { return caml_global_data.toc; }


//Provides: caml_reify_bytecode
//Requires: caml_failwith
function caml_reify_bytecode (code, _sz) {
  if(joo_global_object.toplevelCompile)
    return joo_global_object.toplevelCompile(code);
  else caml_failwith("Toplevel not initialized (toplevelCompile)")
}

//Provides: caml_static_release_bytecode
function caml_static_release_bytecode () { return 0; }

//Provides: caml_static_alloc
//Requires: caml_create_string
function caml_static_alloc (len) { return caml_create_string (len); }

//Provides: caml_static_free
function caml_static_free () { return 0; }

//Provides: caml_realloc_global
//Requires: caml_global_data
function caml_realloc_global (len) {
  if (len + 1 > caml_global_data.length) caml_global_data.length = len + 1;
  return 0;
}

//Provides: caml_dynlink_open_lib
function caml_dynlink_open_lib () { return 0; }

//Provides: caml_dynlink_close_lib
function caml_dynlink_close_lib () { return 0; }

//Provides: caml_dynlink_lookup_symbol
function caml_dynlink_lookup_symbol (_h, _s) {
  return 1;
//  try { eval(s.toString()); return 1; } catch (e) { return 0; };
}

//Provides: caml_dynlink_add_primitive
//Requires: caml_global_data
function caml_dynlink_add_primitive () {
  return caml_global_data.prim_count++;
}

//Provides: caml_dynlink_get_current_libs
function caml_dynlink_get_current_libs () { return [0, 0]; }
