(*
  This module defines the functional unit entries for floating
  point arithmetic.

  TODO: WARNING: check that the instructions set exceptions on invalid rounding modes.
*)
Require Import Kami.All.
Require Import FpuKami.Definitions.
Require Import FpuKami.MulAdd.
Require Import FpuKami.Compare.
Require Import FpuKami.NFToIN.
Require Import FpuKami.INToNF.
Require Import FpuKami.Classify.
Require Import FpuKami.ModDivSqrt.
Require Import FU.
Require Import Fpu.
Require Import List.
Import ListNotations.

Section Fpu.

  Variable Xlen_over_8: nat.
  Variable Flen_over_8: nat.
  Variable Rlen_over_8: nat. (* the "result" length, specifies the size of values stored in the context and update packets. *)

  Variable fu_params : fu_params_type.
  Variable ty : Kind -> Type.

  Local Notation Rlen := (Rlen_over_8 * 8).
  Local Notation Flen := (Flen_over_8 * 8).
  Local Notation Xlen := (Xlen_over_8 * 8).
  Local Notation PktWithException := (PktWithException Xlen_over_8).
  Local Notation ExecContextUpdPkt := (ExecContextUpdPkt Rlen_over_8).
  Local Notation ExecContextPkt := (ExecContextPkt Xlen_over_8 Rlen_over_8).
  Local Notation FullException := (FullException Xlen_over_8).
  Local Notation FUEntry := (FUEntry Xlen_over_8 Rlen_over_8).
  Local Notation RoutedReg := (RoutedReg Rlen_over_8).
  Local Notation NFToINOutput := (NFToINOutput (Xlen - 2)).
  Local Notation INToNFInput := (INToNFInput (Xlen - 2)).

  Local Notation expWidthMinus2 := (fu_params_expWidthMinus2 fu_params).
  Local Notation sigWidthMinus2 := (fu_params_sigWidthMinus2 fu_params).
  Local Notation exp_valid      := (fu_params_exp_valid fu_params).
  Local Notation sig_valid      := (fu_params_sig_valid fu_params).
  Local Notation suffix         := (fu_params_suffix fu_params).
  Local Notation int_suffix     := (fu_params_int_suffix fu_params).
  Local Notation format_field   := (fu_params_format_field fu_params).
  Local Notation exts           := (fu_params_exts fu_params).
  Local Notation exts_32        := (fu_params_exts_32 fu_params).
  Local Notation exts_64        := (fu_params_exts_64 fu_params).

  Local Notation len := ((expWidthMinus2 + 1 + 1) + (sigWidthMinus2 + 1 + 1))%nat.

  Local Notation bitToFN := (@bitToFN ty expWidthMinus2 sigWidthMinus2).
  Local Notation bitToNF := (@bitToNF ty expWidthMinus2 sigWidthMinus2).
  Local Notation fp_get_float := (@fp_get_float ty expWidthMinus2 sigWidthMinus2 Rlen Flen).
  Local Notation csr           := (@csr ty Rlen_over_8).
  Local Notation rounding_mode := (@rounding_mode ty Xlen_over_8 Rlen_over_8).

  Definition add_format_field
    :  UniqId -> UniqId
    := cons (fieldVal fmtField format_field).

  Definition MacInputType
    :  Kind
    := STRUCT {
           (* "fcsr"      :: CsrValue; *)
           "fflags"    :: FflagsValue;
           "muladd_in" :: (MulAdd_Input expWidthMinus2 sigWidthMinus2)
         }.

  Definition MacOutputType
    :  Kind
    := STRUCT {
           (* "fcsr"       :: CsrValue; *)
           "fflags"     :: FflagsValue;
           "muladd_out" :: MulAdd_Output expWidthMinus2 sigWidthMinus2
         }.

  Open Scope kami_expr.

  Definition NF_const_1
    :  NF expWidthMinus2 sigWidthMinus2 @# ty
    := STRUCT {
         "isNaN"  ::= $$false;
         "isInf"  ::= $$false;
         "isZero" ::= $$false;
         "sign"   ::= $$false;
         "sExp"   ::= $0;
         "sig"    ::= $0
       }.

  Definition MacInput (op : Bit 2 @# ty) (context_pkt_expr : ExecContextPkt ## ty) 
    :  MacInputType ## ty
    := LETE context_pkt
         :  ExecContextPkt
         <- context_pkt_expr;
       RetE
         (STRUCT {
            (* "fcsr" ::= #context_pkt @% "fcsr"; *)
            "fflags" ::= #context_pkt @% "fflags";
            "muladd_in"
              ::= (STRUCT {
                     "op" ::= op;
                     "a"  ::= bitToNF (fp_get_float (#context_pkt @% "reg1"));
                     "b"  ::= bitToNF (fp_get_float (#context_pkt @% "reg2"));
                     "c"  ::= bitToNF (fp_get_float (#context_pkt @% "reg3"));
                     "roundingMode"   ::= rounding_mode (#context_pkt);
                     "detectTininess" ::= $$true
                   } : MulAdd_Input expWidthMinus2 sigWidthMinus2 @# ty)
          } : MacInputType @# ty).

  Definition AddInput (op : Bit 2 @# ty) (context_pkt_expr : ExecContextPkt ## ty) 
    :  MacInputType ## ty
    := LETE context_pkt
         :  ExecContextPkt
         <- context_pkt_expr;
       RetE
         (STRUCT {
            (* "fcsr" ::= #context_pkt @% "fcsr"; *)
            "fflags" ::= #context_pkt @% "fflags";
            "muladd_in"
              ::= (STRUCT {
                     "op" ::= op;
                     "a"  ::= bitToNF (fp_get_float (#context_pkt @% "reg1"));
                     "b"  ::= NF_const_1;
                     "c"  ::= bitToNF (fp_get_float (#context_pkt @% "reg2"));
                     "roundingMode"   ::= rounding_mode (#context_pkt);
                     "detectTininess" ::= $$true
                   } : MulAdd_Input expWidthMinus2 sigWidthMinus2 @# ty)
          } : MacInputType @# ty).

  Definition MulInput (op : Bit 2 @# ty) (context_pkt_expr : ExecContextPkt ## ty) 
    :  MacInputType ## ty
    := LETE context_pkt
         :  ExecContextPkt
         <- context_pkt_expr;
       RetE
         (STRUCT {
            (* "fcsr" ::= #context_pkt @% "fcsr"; *)
            "fflags" ::= #context_pkt @% "fflags";
            "muladd_in"
              ::= (STRUCT {
                     "op" ::= op;
                     "a"  ::= bitToNF (fp_get_float (#context_pkt @% "reg1"));
                     "b"  ::= bitToNF (fp_get_float (#context_pkt @% "reg2"));
                     "c"  ::= bitToNF ($0);
                     "roundingMode"   ::= rounding_mode (#context_pkt);
                     "detectTininess" ::= $$true
                   } : MulAdd_Input expWidthMinus2 sigWidthMinus2 @# ty)
          } : MacInputType @# ty).

  Definition MacOutput (sem_out_pkt_expr : MacOutputType ## ty)
    :  PktWithException ExecContextUpdPkt ## ty
    := LETE sem_out_pkt
         :  MacOutputType
         <- sem_out_pkt_expr;
       RetE
         (STRUCT {
            "fst"
              ::= (STRUCT {
                     "val1"
                       ::= Valid (STRUCT {
                             "tag"  ::= Const ty (natToWord RoutingTagSz FloatRegTag);
                             "data" ::= OneExtendTruncLsb Rlen (NFToBit (#sem_out_pkt @% "muladd_out" @% "out"))
                           });
                     "val2"
                       ::= Valid (STRUCT {
                             "tag"  ::= Const ty (natToWord RoutingTagSz FflagsTag);
                             "data" ::= ((csr (#sem_out_pkt @% "muladd_out" @% "exceptionFlags")) : Bit Rlen @# ty)
                           });
                     "memBitMask" ::= $$(getDefaultConst (Array Rlen_over_8 Bool));
                     "taken?" ::= $$false;
                     "aq" ::= $$false;
                     "rl" ::= $$false
                   } : ExecContextUpdPkt @# ty);
            "snd" ::= Invalid
          } : PktWithException ExecContextUpdPkt @# ty).

  Definition Mac
    :  @FUEntry ty
    := {|
         fuName := append "mac" suffix;
         fuFunc
           := fun sem_in_pkt_expr : MacInputType ## ty
                => LETE sem_in_pkt
                     :  MacInputType
                     <- sem_in_pkt_expr;
                   LETE muladd_out
                     :  MulAdd_Output expWidthMinus2 sigWidthMinus2
                     <- MulAdd_expr (#sem_in_pkt @% "muladd_in");
                   RetE
                     (STRUCT {
                        (* "fcsr"       ::= #sem_in_pkt @% "fcsr"; *)
                        "fflags"     ::= #sem_in_pkt @% "fflags";
                        "muladd_out" ::= #muladd_out
                      } : MacOutputType @# ty);
         fuInsts
           := [
                {|
                  instName   := append "fmadd" suffix;
                  extensions := exts;
                  uniqId
                    := [
                         fieldVal fmtField format_field;
                         fieldVal instSizeField ('b"11");
                         fieldVal opcodeField   ('b"10000")
                       ];
                  inputXform  := MacInput $0;
                  outputXform := MacOutput;
                  optMemXform := None;
                  instHints := falseHints<|hasFrs1 := true|><|hasFrs2 := true|><|hasFrs3 := true|><|hasFrd := true|> 
                |};
                {|
                  instName   := append "fmsub" suffix;
                  extensions := exts;
                  uniqId
                    := [
                         fieldVal fmtField format_field;
                         fieldVal instSizeField ('b"11");
                         fieldVal opcodeField   ('b"10001")
                       ];
                  inputXform  := MacInput $1;
                  outputXform := MacOutput;
                  optMemXform := None;
                  instHints := falseHints<|hasFrs1 := true|><|hasFrs2 := true|><|hasFrs3 := true|><|hasFrd := true|> 
                |};
                {|
                  instName   := append "fnmsub" suffix;
                  extensions := exts;
                  uniqId
                    := [
                         fieldVal fmtField format_field;
                         fieldVal instSizeField ('b"11");
                         fieldVal opcodeField   ('b"10010")
                       ];
                  inputXform  := MacInput $2;
                  outputXform := MacOutput;
                  optMemXform := None;
                  instHints := falseHints<|hasFrs1 := true|><|hasFrs2 := true|><|hasFrs3 := true|><|hasFrd := true|> 
                |};
                {|
                  instName   := append "fnmadd" suffix;
                  extensions := exts;
                  uniqId
                    := [
                         fieldVal fmtField format_field;
                         fieldVal instSizeField ('b"11");
                         fieldVal opcodeField   ('b"10011")
                       ];
                  inputXform  := MacInput $3;
                  outputXform := MacOutput;
                  optMemXform := None;
                  instHints := falseHints<|hasFrs1 := true|><|hasFrs2 := true|><|hasFrs3 := true|><|hasFrd := true|> 
                |};
                {|
                  instName   := append "fadd" suffix;
                  extensions := exts;
                  uniqId
                    := [
                         fieldVal fmtField format_field;
                         fieldVal instSizeField ('b"11");
                         fieldVal opcodeField   ('b"10100");
                         fieldVal rs3Field      ('b"00000")
                       ];
                  inputXform  := AddInput $0;
                  outputXform := MacOutput;
                  optMemXform := None;
                  instHints := falseHints<|hasFrs1 := true|><|hasFrs2 := true|><|hasFrd := true|> 
                |};
                {|
                  instName   := append "fsub" suffix;
                  extensions := exts;
                  uniqId
                    := [
                         fieldVal fmtField format_field;
                         fieldVal instSizeField ('b"11");
                         fieldVal opcodeField   ('b"10100");
                         fieldVal rs3Field      ('b"00001")
                       ];
                  inputXform  := AddInput $1;
                  outputXform := MacOutput;
                  optMemXform := None;
                  instHints := falseHints<|hasFrs1 := true|><|hasFrs2 := true|><|hasFrd := true|> 
                |};
                {|
                  instName   := append "fmul" suffix;
                  extensions := exts;
                  uniqId
                    := [
                         fieldVal fmtField format_field;
                         fieldVal instSizeField ('b"11");
                         fieldVal opcodeField   ('b"10100");
                         fieldVal rs3Field      ('b"00010")
                       ];
                  inputXform  := MulInput $0;
                  outputXform := MacOutput;
                  optMemXform := None;
                  instHints := falseHints<|hasFrs1 := true|><|hasFrs2 := true|><|hasFrd := true|> 
                |}
              ]
      |}.

  Close Scope kami_expr.

End Fpu.