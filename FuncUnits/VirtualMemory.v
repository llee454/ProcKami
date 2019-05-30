(*
  This module defines the Page Table Walker which translates virtual
  memory addresses into physical memory addresses.

  See Section 4.3.2.

  TODO: Replace references to VAddr with PAddr.
*)
Require Import Kami.All.
Require Import FU.
Require Import ProcessorCore.
Require Import MemUnit.
Require Import Vector.
Import VectorNotations.
Require Import List.
Import ListNotations.

Section pt_walker.

  Variable name: string.
  Variable Xlen_over_8: nat.
  Variable Rlen_over_8: nat.
  Variable lgMemSz : nat.
  Variable napot_granularity : nat.
  Variable levels : nat.
  Variable ty : Kind -> Type.

  Local Notation "^ x" := (name ++ "_" ++ x)%string (at level 0).
  Local Notation Xlen := (Xlen_over_8 * 8).
  Local Notation Rlen := (Rlen_over_8 * 8).
  Local Notation VAddr := (Bit Xlen).
  Local Notation Data := (Bit Rlen).
  Local Notation PktWithException := (PktWithException Xlen_over_8).
  Local Notation FullException := (FullException Xlen_over_8).
  Local Notation memRead := (memRead name Xlen_over_8 Rlen_over_8 lgMemSz napot_granularity).

  Open Scope kami_expr.
  Open Scope kami_action.

  Section pte.
    Variable page_size : nat. (* when PAGESIZE=2^n, page_size = log2 PAGESIZE = n *)
    Variable pte_width : nat.
    Variable num_ppns : nat.
    Variable ppn_width : nat.
    Variable last_ppn_width : nat.

    Local Definition vm_access_width := 2.
    Local Definition vm_access_inst := 0.
    Local Definition vm_access_load := 1.
    Local Definition vm_access_samo := 2.

    Local Definition offset_width := 9.
 
    (* See figure 4.15 *)
    Definition pte_valid (pte : Bit pte_width @# ty)
      :  Bool @# ty
      := unsafeTruncLsb 1 pte == $1.

    Definition pte_read (pte : Bit pte_width @# ty)
      :  Bool @# ty
      := (unsafeTruncLsb 8 pte)$#[1:1] == $1.

    Definition pte_write (pte : Bit pte_width @# ty)
      :  Bool @# ty
      := (unsafeTruncLsb 8 pte)$#[2:2] == $1.

    Definition pte_execute (pte : Bit pte_width @# ty)
      :  Bool @# ty
      := (unsafeTruncLsb 8 pte)$#[3:3] == $1.

    (* See 4.3.2 item 8 *)
    Definition vaddr_offset
      (level : nat)
      (vaddr : VAddr @# ty)
      :  VAddr @# ty
      := let width
           := (offset_width + (level * ppn_width))%nat in
         ZeroExtendTruncLsb Xlen
           (unsafeTruncLsb width vaddr).

    Definition pte_ppn
      (ppn_index : nat)
      (pte : Bit pte_width @# ty)
      :  prod nat (VAddr @# ty)
      := let width
           := if Nat.eqb (S ppn_index) levels
                then last_ppn_width
                else ppn_width in
         let lb := (offset_width + (ppn_index * ppn_width))%nat in
         let ub := (lb + width)%nat in
         (lb,
          ZeroExtendTruncLsb Xlen
            (ZeroExtendTruncMsb width
              (unsafeTruncLsb ub pte))).

    Definition pte_ppns
      (ppn_index_ub : nat)
      (ppn_index_lb : nat)
      (pte : Bit pte_width @# ty)
      :  VAddr @# ty
      := fold_right
           (fun (ppn_index : nat) (acc : VAddr @# ty)
             => let ppn := pte_ppn ppn_index pte in
                ((snd ppn << ($(fst ppn) : Bit (Nat.log2_up Xlen) @# ty) & acc)))
           $0
           (range ppn_index_lb ppn_index_ub).

    (* TODO See 4.3.2 item 5 *)
    Definition pte_grant
      (access_type : Bit vm_access_width @# ty)
      (pte : Bit pte_width @# ty)
      :  Bool @# ty
      := $$true.

    (* TODO See 4.3.2 item 6 *)
    Definition pte_aligned
      (level : nat)
      (pte : Bit pte_width @# ty)
      :  Bool @# ty
      := $$true.

    (* TODO See 4.3.2 item 8 *)
    Definition pte_address
      (level : nat)
      (pte : Bit pte_width @# ty)
      (vaddr : VAddr @# ty)
      : VAddr @# ty
      := (pte_ppns levels level pte &
          vaddr_offset level vaddr).

    Definition vm_exception
      (access_type : Bit vm_access_width @# ty)
      :  PktWithException VAddr @# ty
      := STRUCT {
           "fst" ::= $0;
           "snd"
             ::= Valid
                   (STRUCT {
                      "exception"
                        ::= Switch access_type Retn Exception With {
                              ($vm_access_inst : Bit vm_access_width @# ty)
                                ::= ($InstPageFault : Exception @# ty);
                              ($vm_access_load : Bit vm_access_width @# ty)
                                ::= ($LoadPageFault : Exception @# ty);
                              ($vm_access_samo : Bit vm_access_width @# ty)
                                ::= ($SAmoPageFault : Exception @# ty)
                            };
                      "value"     ::= $0 (* TODO *)
                    } : FullException @# ty)
         } : PktWithException VAddr @# ty.

    (*
      See 4.3.2
    *)
    Definition pte_translate
      (mem_read_index : nat)
      (level : nat)
      (mode : PrivMode @# ty)
      (access_type : Bit vm_access_width @# ty)
      (next_level : VAddr @# ty -> ActionT ty (PktWithException VAddr))
      (address : VAddr @# ty)
      :  ActionT ty (PktWithException VAddr)
      := LETA read_pte
           :  PktWithException Data
           <- memRead mem_read_index mode address;
         LET pte
           :  Bit pte_width
           <- unsafeTruncLsb pte_width (#read_pte @% "fst");
         (* item 2 *)
         If #read_pte @% "snd" @% "valid"
           then
             Ret
               (STRUCT {
                  "fst" ::= $0;
                  "snd" ::= #read_pte @% "snd"
                } : PktWithException VAddr @# ty)
           else
             (* item 3 *)
             (If !pte_valid #pte || (!pte_read #pte && pte_write #pte)
               then Ret (vm_exception access_type)
               else
                 (* item 4 *)
                 (If !pte_read #pte && !pte_execute #pte
                   then
                     (if Nat.eqb level 0
                       then Ret (vm_exception access_type)
                       else LET address
                              :  VAddr
                              (* TODO fix calc. *)
                              <- ZeroExtendTruncLsb Xlen
                                   ((pte_ppns levels level #pte) << ($page_size : Bit 12 @# ty)); 
                            LETA result
                              :  PktWithException VAddr
                              <- next_level #address;
                            Ret #result)
                   else (* item 5 and 6 *)
                     (If !pte_grant access_type #pte ||
                        !pte_aligned level #pte
                       then Ret (vm_exception access_type)
                       else (* TODO add item 7 *)
                         (* item 8 *)
                         Ret
                           (STRUCT {
                              "fst" ::= pte_address level #pte address;
                              "snd" ::= Invalid
                            } : PktWithException VAddr @# ty)
                       as result;
                     Ret #result)
                   as result;
                 Ret #result)
               as result;
             Ret #result)
           as result;
         Ret #result.

    Definition pt_walker
      (mem_read_index : nat)
      (mode : PrivMode @# ty)
      (access_type : Bit vm_access_width @# ty)
      (address : VAddr @# ty)
      :  ActionT ty (PktWithException VAddr)
      := fold_right
           (fun (level : nat) (acc : VAddr @# ty -> ActionT ty (PktWithException VAddr))
             => pte_translate
                  (mem_read_index + level)
                  level
                  mode
                  access_type
                  acc)
           (* See 4.3.2 item 4 *)
           (fun address : VAddr @# ty
             => Ret (vm_exception access_type))
           (seq 0 levels)
           address.

  End pte.

  Close Scope kami_action.
  Close Scope kami_expr.

End pt_walker.
