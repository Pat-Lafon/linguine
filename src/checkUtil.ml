open Util
open GatorAst
open GatorAstPrinter
open Contexts

exception TypeException of string

let line_number (meta : metadata) : string = 
  ("Line: " ^ string_of_int(meta.pos_lnum))
let error cx s = raise (TypeException(line_number cx.meta ^ " -- " ^ s))

(* Produces an empty set of gator contexts with a starting metadata *)
let init meta = let b = 
  {t=Assoc.empty; g=Assoc.empty; d=Assoc.empty; c=Assoc.empty; p=Assoc.empty; l=Assoc.empty } in
  {m=Assoc.empty; ps=Assoc.empty; pm=Assoc.empty; member=None; meta=meta; _bindings=b }

let with_m cx m' = {cx with m=m'}
let with_ps cx ps' = {cx with ps=ps'}
let with_pm cx pm' = {cx with pm=pm'}
let with_meta cx meta' = {cx with meta=meta'}
let with_member cx s = {cx with member=Some s}
let clear_member cx = {cx with member=None}

let get_m cx x = if Assoc.mem x cx.m then Assoc.lookup x cx.m else 
  error cx ("Undefined modifiable item " ^ x)
let get_ps cx x = if Assoc.mem x cx.ps then Assoc.lookup x cx.ps else 
  error cx ("Undefined canonical item " ^ x)
let get_pm cx x = if Assoc.mem x cx.pm then Assoc.lookup x cx.pm else 
  error cx (x ^ " not found in parameterization " ^ string_of_parameterization cx.pm)

(* Finds which context in which to find the given string *)
let find_safe cx x =
  if Assoc.mem x cx._bindings.l then match Assoc.lookup x cx._bindings.l with
  | CTau -> Some (Tau (Assoc.lookup x cx._bindings.t))
  | CGamma -> Some (Gamma (Assoc.lookup x cx._bindings.g))
  | CDelta -> Some (Delta (Assoc.lookup x cx._bindings.d))
  | CChi -> Some (Chi (Assoc.lookup x cx._bindings.c))
  | CPhi -> Some (Phi (Assoc.lookup x cx._bindings.p))
  else None

(* Binds a string with value to the correct lookup context *)
let bind (cx : contexts) (x : string) (b : binding) : contexts =
  if Assoc.mem x cx._bindings.l
  then error cx ("Duplicate use of the name " ^ x) else 
  let update_bindings b' = {cx with _bindings=b'} in
  let _b = cx._bindings in
  match b with
  | Tau t' ->   update_bindings { _b with l=Assoc.update x CTau _b.l; t=Assoc.update x t' _b.t }
  | Gamma g' -> update_bindings { _b with l=Assoc.update x CGamma _b.l; g=Assoc.update x g' _b.g }
  | Delta d' -> update_bindings { _b with l=Assoc.update x CDelta _b.l; d=Assoc.update x d' _b.d }
  | Chi c' ->   update_bindings { _b with l=Assoc.update x CChi _b.l; c=Assoc.update x c' _b.c }
  | Phi p' ->   update_bindings { _b with l=Assoc.update x CPhi _b.l; p=Assoc.update x p' _b.p }

(* Clears the given lookup context of elements *)
let clear (cx : contexts) (b : binding_context) : contexts =
  let update_bindings b' = {cx with _bindings=b'} in
  let _b = cx._bindings in
  let build_l l xs = Assoc.create (List.fold_left (fun acc (x, v) -> 
    if List.mem x xs then acc else (x, v)::acc) [] l) in
  let clear c = build_l (Assoc.bindings _b.l) (List.map fst (Assoc.bindings c)) in
  match b with
  | CTau ->   update_bindings { _b with l=clear _b.t; t=Assoc.empty }
  | CGamma -> update_bindings { _b with l=clear _b.g; g=Assoc.empty }
  | CDelta -> update_bindings { _b with l=clear _b.d; d=Assoc.empty }
  | CChi ->   update_bindings { _b with l=clear _b.c; c=Assoc.empty }
  | CPhi ->   update_bindings { _b with l=clear _b.p; p=Assoc.empty }

let add_function (cx : contexts) (f : fn_typ) : contexts =
  let update_bindings b' = {cx with _bindings=b'} in
  let _b = cx._bindings in
  let _,_,id,_,_,_ = f in
  if Assoc.mem id _b.p
  then let p' = f::Assoc.lookup id _b.p in update_bindings { _b with p=Assoc.update id p' _b.p }
  else bind cx id (Phi [f])

let ignore_typ (t : typ) : unit = ignore t
let ignore_dexp (d : dexp) : unit = ignore d
let ignore_typ_context (t : typ Assoc.context) : unit = ignore t
let string_of_fn_inv ((s, tl) : fn_inv) : string = 
  s ^ "<" ^ string_of_list string_of_typ tl ^ ">"
let debug_fail (cx : contexts) (s : string) =
  failwith (line_number cx.meta ^ "\t" ^ s)
let string_of_tau (pm, t : tau) =
  string_of_parameterization pm ^ " " ^  string_of_typ t
let string_of_mu (ml : mu) =  
  string_of_mod_list ml
let string_of_gamma (g : gamma) =
  string_of_typ g
let string_of_delta (f : delta) =
  string_of_dexp f
let string_of_chi (p,d : chi) =
  "implements " ^ p ^ " with dimension " ^ string_of_dexp d
let string_of_phi (p : phi) =
  string_of_list string_of_fn_typ p
let string_of_psi (ps : psi) : string =
  string_of_list (fun (t, p) -> "(" ^ string_of_typ t ^ ", " ^ string_of_fn_inv p ^ ")") ps
let option_clean (x : 'a option) : 'a =
  match x with | Some x -> x | None -> failwith "Failed option assumption"

let check_member (cx : contexts) (check : string->'a option) (x : string) : 'a option =
  match cx.member with
  | Some c -> let res = check (c ^ "."  ^ x) in 
    (match res with
    | Some _ -> res
    | None -> check x)
  | None -> check x

let get_typ (cx : contexts) (id : string) : tau =
  let get_typ_safe x = 
    match find_safe cx x with
    | Some Tau t -> Some t
    | _ -> None 
  in
  match check_member cx get_typ_safe id with
  | Some t -> t
  | None -> error cx ("Undefined type " ^ id)

let get_var (cx : contexts) (x : string) : gamma =
  match find_safe cx x with
  | Some Gamma g -> g
  | _ -> error cx ("Undefined variable " ^ x)

let get_frame (cx : contexts) (x : string) : delta =
  match find_safe cx x with
  | Some Delta d -> d
  | _ -> error cx ("Undefined frame " ^ x)

let get_coordinate (cx : contexts) (x : string) : chi =
  match find_safe cx x with
  | Some Chi c -> c
  | _ -> error cx ("Undefined coordinate scheme " ^ x)

let get_functions_safe (cx : contexts) (id : string) : phi =
  let get_fn_safe x = 
    match find_safe cx x with
    | Some Phi p -> if List.length p > 0 then Some p else None
    | _ -> None
  in
  match check_member cx get_fn_safe id with
  | Some t -> t
  | None -> []

let get_functions (cx : contexts) (id : string) : phi = 
  match get_functions_safe cx id with
  | [] -> error cx ("No type definition for function " ^ id)
  | p -> p