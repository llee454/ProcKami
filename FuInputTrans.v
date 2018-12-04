(*
  This section defines the Input Transformer generator. The Input
  Transformer Generator uses the instruction database to generate
  the Kami let expression that represents the Input Transformer. The
  Input Transformer accepts an execution context packet from the
  Packager and returns a functional unit-specific execution packet
  that is passed to the Router.

  TODO: Replace the optional packet type with the Maybe kind
  TODO: Use Kami notations where applicable.
  TODO: Replace ITEs with ORs. unpack (IF (input-uniqid == current-inst-id) then pack inputVal else 0 || ...)
  
*)
Require Import Kami.All.
Require Import FU.

Section input_trans.

(* Represents the instruction width. *)
Variable Xlen_over_8 : nat.

(* Maps Kami types onto their denotational gallina type. *)
Variable ty : Kind -> Type.

(* Represents the type of raw instructions. *)
Definition raw_inst_type : Type := LetExprSyntax ty Inst.

(*  Represents the type of functional unit entries. *)
Definition func_unit_entry_type : Type := @FUEntry Xlen_over_8 ty.

(* Represents the type of instruction entries. *)
Definition inst_entry_type (sem_input_kind sem_output_kind : Kind)
  := @InstEntry Xlen_over_8 ty sem_input_kind sem_output_kind.

(* Represents the kind of execution context packets. *)
Definition exec_context_packet_kind : Kind
  := ExecContextPkt Xlen_over_8.

(* Represents the type of execution context packets. *)
Definition exec_context_packet_type : Type
  := Expr ty (SyntaxKind exec_context_packet_kind).

(* *)
Definition exec_context_packet_expr_type : Type
  := LetExprSyntax ty exec_context_packet_kind.

(*
  Accepts an instruction entry and an execution context packet that
  contains a bit string representing a raw RISC-V instruction and
  returns a Kami expression representing a boolean that is true
  iff the instruction is the same type as the instruction entry.
*)
Variable trans_optional_packet_enabled
  : forall sem_input_kind sem_output_kind : Kind,
    inst_entry_type sem_input_kind sem_output_kind ->
    exec_context_packet_expr_type ->
    LetExprSyntax ty Bool.

(* Represents optional packets. *)
Definition optional_packet_kind (packet_kind : Kind) : Kind
  := STRUCT {"enabled" :: Bool; "packet" :: packet_kind}.

(*
*)
Definition optional_packet_type (packet_kind : Kind) : Type
  := Expr ty (SyntaxKind (optional_packet_kind packet_kind)).

(*
  Represents optional packets.

  Note: An optional packet is a packet with an additional boolean
  field that is set to true when the data contained within the packet
  is valid. This is equivalent to a option type where enabled =
  false denotes Nothing.
*)
Definition optional_packet_expr_type (packet_kind : Kind) : Type
  := LetExprSyntax ty (optional_packet_kind packet_kind).

(*
  Accepts a list of functional units and returns the type of
  functional-unit specific input packets that are accepted by one
  of the given units.
*)
Definition valid_packet_type (func_units : list func_unit_entry_type) : Type
  := {packet_kind : Kind |
       exists func_unit, In func_unit func_units /\
                         fuInputK func_unit = packet_kind}.

(*
  Accepts a list of functional units and returns the type of
  functional-unit specific input optional packets that are a accepted
  by one of the given units.
*)
Definition valid_optional_packet_expr_type (func_units : list func_unit_entry_type) : Type
  := sigT (fun packet_kind : valid_packet_type func_units
            => optional_packet_expr_type (proj1_sig packet_kind)).

Open Scope kami_expr.

(*
  Accepts a packet and returns a Kami expression that wraps the
  packet in an optional packet struct.
*)
Definition optional_packet
  (packet_type : Kind)
  (input_packet : Expr ty (SyntaxKind packet_type))
  (enabled : Expr ty (SyntaxKind Bool))
  :  optional_packet_expr_type packet_type
  := RetE (
       STRUCT {
         "enabled" ::= enabled;
         "packet"  ::= input_packet
       }).

(*
  Accepts an instruction record and an execution context packet
  and returns a functional unit-specific execution packet.
*)
Definition trans_inst
  (sem_input_kind sem_output_kind : Kind)
  (inst_entry : inst_entry_type sem_input_kind sem_output_kind)
  (exec_context_packet : exec_context_packet_expr_type)
  :  optional_packet_expr_type sem_input_kind
  := LETE packet : sem_input_kind <- inputXform inst_entry exec_context_packet;
     LETE enabled : Bool <-
       trans_optional_packet_enabled
         inst_entry
         exec_context_packet;
     (optional_packet (#packet) (#enabled)).

Close Scope kami_expr.

(*
  Accepts a list of instruction records and returns a Kami let
  expression that accepts an execution context packet and returns
  an execution packet for the instruction passed in the execution
  context packet. Note: the returned packet is optional. If none
  of the instruction records match the given instruction the let
  expression returns the packet generated by the last instruction's
  transform function with a false enabled signal.
*)
Definition trans_insts (sem_input_kind sem_output_kind : Kind)
  : forall inst_entries : list (inst_entry_type sem_input_kind sem_output_kind),
    0 < length inst_entries ->
    exec_context_packet_expr_type ->
    optional_packet_expr_type sem_input_kind
  := list_rect
       (fun inst_entries
         => 0 < length inst_entries ->
            exec_context_packet_expr_type ->
            optional_packet_expr_type sem_input_kind)
       (* I. empty list of instruction records case. *)
       (fun H _
         => False_rect (optional_packet_expr_type sem_input_kind)
              ((Nat.nlt_0_r 0) H)) 
       (* II. multiple instructio records case. *)
       (fun inst_entry inst_entries
         (F : 0 < length inst_entries ->
              exec_context_packet_expr_type ->
              optional_packet_expr_type sem_input_kind)
         _ exec_context_packet
         => sumbool_rect 
              (fun _ => optional_packet_expr_type sem_input_kind)
              (* A. multiple remaining entries case. *)
              (fun H : 0 < length inst_entries
                => (LETE inst_entry_packet
                     :  optional_packet_kind sem_input_kind
                     <- trans_inst inst_entry exec_context_packet;
                   LETE insts_entry_packet
                     :  optional_packet_kind sem_input_kind
                     <- F H exec_context_packet;
                   RetE ((ITE
                          (ReadStruct (#inst_entry_packet) Fin.F1) 
                          (#inst_entry_packet)
                          (#insts_entry_packet) : optional_packet_type sem_input_kind)))%kami_expr)
              (* B. last instruction case. *)
              (fun _ 
                => LETE inst_entry_packet
                     :  optional_packet_kind sem_input_kind
                     <- trans_inst inst_entry exec_context_packet;
                   RetE (#inst_entry_packet))%kami_expr
              (Compare_dec.lt_dec 0 (length inst_entries))).

(*
  Accepts the functional unit record and returns a Kami expression
  that accepts an execution context packet and returns a functional
  unit-specific input packet encoding the unit's arguments.
*)
Definition trans_func_unit
  (func_unit : func_unit_entry_type)
  (func_unit_insts_not_empty : 0 < length (fuInsts func_unit))
  (exec_context_packet : exec_context_packet_expr_type)
  :  optional_packet_expr_type (fuInputK func_unit)
  := list_rect
       (fun insts => 0 < length insts -> optional_packet_expr_type (fuInputK func_unit))
       (fun H : 0 < length nil
         => False_rect (optional_packet_expr_type (fuInputK func_unit))
              (Nat.nlt_0_r 0 H))
       (fun inst insts _ (H : 0 < length (inst :: insts))
         => trans_insts
              (inst :: insts)
              H
              exec_context_packet)
       (fuInsts func_unit)
       func_unit_insts_not_empty.

(*
  The problem here is that we cannot return different kinds in a Kami
  ITE expression. both branches must return the same Kami kind. One
  way around this is to define a struct in which each element in the
  struct corresponds to a functional unit and consists of a pair
  of the sem_input kind associated with the functional unit and a
  "selected" signal indicating that this is the substruct carrying
  the packet.

  To use this approach, we must define a generator function that
  accepts a list of functional units and returns a Kami struct
  definition that has the required structure.

  For example:

  STRUCT {
    "ALU" :: STRUCT {
      "selected" :: Bool;
      "packet"   :: _
    };
    _
  }
*)

(* Appends a value to the end of generated sequence. *)
Definition vec_append (A : Set) (x : A) (n : nat) (ref : Fin.t n -> A) (k : Fin.t (S n))
  :  A
  := Fin.t_rec
       (fun m (_ : Fin.t m) => m = S n -> A)
       (fun m _ => x)
       (fun m index _ (H : S m = S n)
         => ref (@Fin.cast m index n (eq_add_S m n H)))
       (S n)
       k
       (eq_refl (S n)).

(*
Compute (@vec_append nat 5 4 (fun k => let (n, _) := @Fin.to_nat 4 k in n) (Fin.F1)).
Compute (@vec_append nat 5 4 (fun k => let (n, _) := @Fin.to_nat 4 k in n) (Fin.FS (Fin.F1))).
Compute (@vec_append nat 5 4 (fun k => let (n, _) := @Fin.to_nat 4 k in n) (Fin.FS (Fin.FS (Fin.F1)))).
Compute (@vec_append nat 5 4 (fun k => let (n, _) := @Fin.to_nat 4 k in n) (Fin.FS (Fin.FS (Fin.FS (Fin.F1))))).
Compute (@vec_append nat 5 4 (fun k => let (n, _) := @Fin.to_nat 4 k in n) (Fin.FS (Fin.FS (Fin.FS (Fin.FS (Fin.F1)))))).
*)

(*
  Accepts a list of functional units and returns a struct that lists
  the optional packet structures associated with each functional
  unit keyed by name.

  Note: the order in which functional units are listed is reversed.
*)
Definition trans_func_units_packet_kind (func_units : list func_unit_entry_type)
  :  0 < length func_units -> Kind
  := list_rec
       (fun func_units => 0 < length func_units -> Kind)
       (fun H : 0 < 0
         => False_rec _
              (Nat.nlt_0_r 0 H))
       (fun func_unit func_units
         (F : 0 < length func_units -> Kind)
         (_ : 0 < length (func_unit :: func_units))
         => sumbool_rec
              (fun _ => Kind)
              (fun H : 0 < length func_units
                => @Kind_rec
                     (fun _ => Kind)
                     (Bool)
                     (fun _ => Bool)
                     (fun n
                         (getKind : Fin.t n -> Kind)
                         (_ : Fin.t n -> Kind)
                         (getLabel : Fin.t n -> string)
                       => @Struct (S n)
                            (@vec_append Kind (optional_packet_kind (fuInputK func_unit)) n getKind)
                            (@vec_append string (fuName func_unit) n getLabel)
                            )
                     (fun _ _ _ => Bool) 
                     (F H))
              (fun _ : ~ 0 < length func_units
                => STRUCT {
                     (fuName func_unit) :: (optional_packet_kind (fuInputK func_unit))
                   })
              (Compare_dec.lt_dec 0 (length func_units)))
       func_units.

(*
*)
Definition trans_func_units_packet
  (HI : forall func_unit, 0 < length (fuInsts func_unit))
  (func_units : list func_unit_entry_type)
  (exec_context_packet : exec_context_packet_expr_type)
  :  0 < length func_units ->
     trans_func_units_packet_kind func_units
  := list_rect 
       (fun func_units
         => 0 < length func_unts -> trans_func_units_packet_kind func_units)
       (fun H : 0 < 0
         => False_rec _
              (Nat.nlt_0_r 0 H))
       (fun func_unit func_units
         (F : 0 < length func_units -> trans_func_units_packet_kind func_units)
         (_ : 0 < length (func_unit :: func_units))
         => sumbool_rec
              (fun _ => trans_func_units_packet_kind (func_unit :: func_units))
              (fun H : 0 < length func_units
                => Struct
                     (@vec_append (optional_packet_kind (fuInputK func_unit)) 
                       (trans_func_unit
                         func_unit
                         (HI func_unit)
                         exec_context_packet)
                       (length func_units)
                       

(*
  Now I need a way to create a value of the given type. It's just a struct of optional packets.

  One option would be to accept

  [(functional unit entry, optional packet), ...]

  and then return a struct having the expected form.

*)
(*
Variable trans_func_units_packet
  : forall packets : list ({entry : func_unit_entry_type & (pair func_unit_entry_type (Expr ty (SyntaxKind (fuInputK entry))))}), bool.
*)

(*
  (packets : list (sigT (
    fun fun_unit_entry_type => (pair func_unit_entry_type) 
*)

(*
  Accepts a set of functional units, an assertion that all of these
  units has one or more associated instructions, a raw instruction
  expression, an assertion that the raw instruction matches one
  of the entries associated with the given functional units, and
  returns a Kami let expression that accepts an
*)
(*
Definition trans_func_units
  (func_units : list func_unit_entry_type)
  (exec_context_packet : exec_context_packet_expr_type)
  :  0 < length func_units ->
     (forall func_unit, In func_unit func_units -> 0 < length (fuInsts func_unit)) ->
     valid_optional_packet_expr_type func_units
  := list_rect
       (fun func_units
         => 0 < length func_units ->
            (forall func_unit, In func_unit func_units -> 0 < length (fuInsts func_unit)) ->
            valid_optional_packet_expr_type func_units)
       (fun (H : 0 < length nil) _
         => False_rect _
              (Nat.nlt_0_r 0 H))
       (fun func_unit func_units
           (F : 0 < length func_units ->
                (forall func_unit, In func_unit func_units -> 0 < length (fuInsts func_unit)) ->
                (valid_optional_packet_expr_type func_units))
           (_ : 0 < length (func_unit :: func_units))
           (H : forall fu, In fu (func_unit :: func_units) -> 0 < length (fuInsts fu))
         => let H0
              :  In func_unit (func_unit :: func_units)
              := or_introl (In func_unit func_units) (eq_refl func_unit) in
            let H1
              :  forall fu, In fu func_units -> 0 < length (fuInsts fu)
              := fun fu H2
                   => H fu (or_intror (func_unit = fu) H2) in
            sumbool_rect
              (fun _ => valid_optional_packet_expr_type (func_unit :: func_units))
              (fun H2 : 0 < length func_units
                => sigT_rect
                     (fun _ : valid_optional_packet_expr_type func_units
                       => valid_optional_packet_expr_type (func_unit :: func_units))
                     (sig_rect
                       (fun packet_type : valid_packet_type (func_unit :: func_units)
                         => optional_packet_expr_type (proj1_sig packet_type) ->
                            valid_optional_packet_expr_type (func_unit :: func_units))
                       (fun (sem_input_kind : Kind)
                            (_ : exists fu, In fu (func_unit :: func_units) /\ fuInputK fu = sem_input_kind)
                            (sem_input_expr : optional_packet_expr_type sem_input_kind)
                         => LETE func_unit_packet
                              :  optional_packet_kind (fuInputK func_unit)
                              <- trans_func_unit func_unit (H func_unit H0) exec_context_packet;
                            LETE func_units_packet
                              :  optional_packet_kind sem_input_kind
                              <- sem_input_expr;
                            RetE ((ITE
                                   (ReadStruct (#func_unit_packet) Fin.F1)
                                   (#func_unit_packet)
                                   (#func_units_packet))))%kami_expr)
                     (F H2 H1))
              (fun _
                => LETE func_unit_packet
                     :  optional_packet_kind (fuInputK func_unit)
                     <- trans_func_unit func_unit (H H0) exec_context_packet;
                   RetE (#func_unit_packet))%kami_expr
              (Compare_dec.lt_dec 0 (length func_units))).
*)
(*
  The enabled flag is set by the raw_inst_match_inst function defined in InstMatcher.v. I can prove that if the enabled flag returns true for any of the above functions, raw_inst_match_funct_units must return true. I can also prove the equivalence the other way - i.e. that raw_inst_match_funct_units implies that the enabled flag returned by the optional packet must be true.

  I want to remove the optional packet wrapper and know that the packet returned for valid instructions is transformed by the correct transform function.

  The transformer is correct iff the correct transformer is applied to the execution context packet when the instruction is valid.

  let's formalize this correctness property.

  Also verify that the enabled flag is always true of valid instructions.
*)

(*
  Accepts an execution exception packet and returns a functional
  unit-specific execution packet that stores the formatted argument
  values.
*)
(*
Variable trans_func_units
  : forall (func_units : list func_unit_entry_type),
      (forall func_unit, In func_unit func_units -> 0 < length (fuInsts func_unit)) ->
      exec_context_packet_expr_type ->
      sigT (fun packet_kind : valid_packet_type func_units
             => optional_packet_expr_type (proj1_sig packet_kind)).
*)
(*
  If I have a valid instruction, then I know that one of the functional units contains an instruction that matches the given raw instruction.
  The decoder should return a dependent type with a property that exists func_unit, exists instr in func_unit where instr_match instr raw string.
  We still need to compare the instr against each of the instruction records listed under each func unit to find the matching instruction record, but we know that in the end, the enabled flag in the optional packet must be true. That is, we cannot return "nothing".

  Additionally, the functional units all contain one or more instructions. None of the functional units contain no instructions. We should change the type of fuInsts to a nonempty list or add a hypothesis asserting this fact.
  Once the functional unit records have been hard coded, I can add a theorem asserting that none of the functional units in the database have no entries.

  
*)


End input_trans.