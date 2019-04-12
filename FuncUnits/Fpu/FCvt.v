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
Require Import FpuKami.Round.
Require Import FU.
Require Import Fpu.
Require Import List.
Import ListNotations.

Section Fpu.

  Variable Xlen_over_8: nat.
  Variable Flen_over_8: nat.
  Variable Rlen_over_8: nat.

  Variable fu_params : fu_params_type.
  Variable ty : Kind -> Type.

  Local Notation Rlen := (8 * Rlen_over_8).
  Local Notation Flen := (8 * Flen_over_8).
  Local Notation Xlen := (8 * Xlen_over_8).
  Local Notation PktWithException := (PktWithException Xlen_over_8).
  Local Notation ExecContextUpdPkt := (ExecContextUpdPkt Rlen_over_8).
  Local Notation ExecContextPkt := (ExecContextPkt Xlen_over_8 Rlen_over_8).
  Local Notation FullException := (FullException Xlen_over_8).
  Local Notation FUEntry := (FUEntry Xlen_over_8 Rlen_over_8).
  Local Notation RoutedReg := (RoutedReg Rlen_over_8).
  Local Notation noUpdPkt := (@noUpdPkt Rlen_over_8 ty).

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
  Local Notation NFToBit := (@NFToBit ty expWidthMinus2 sigWidthMinus2).
  Local Notation fp_get_float  := (@fp_get_float ty expWidthMinus2 sigWidthMinus2 Rlen Flen).
  Local Notation csr           := (@csr ty Rlen_over_8).
  Local Notation rounding_mode := (@rounding_mode ty Xlen_over_8 Rlen_over_8).

  Open Scope kami_expr.

  Definition Float_Int_Input (signed : Bool @# ty) (context_pkt_expr : ExecContextPkt ## ty)
    :  NFToINInput expWidthMinus2 sigWidthMinus2 ## ty
    := LETE context_pkt
         <- context_pkt_expr;
       RetE
         (STRUCT {
            "inNF"         ::= bitToNF (fp_get_float (#context_pkt @% "reg1"));
            "roundingMode" ::= rounding_mode (#context_pkt);
            "signedOut"    ::= signed
          } : NFToINInput expWidthMinus2 sigWidthMinus2 @# ty).

  Definition Float_Int_Output (size : nat) (sem_out_pkt_expr : NFToINOutput size ## ty)
    :  PktWithException ExecContextUpdPkt ## ty
    := LETE sem_out_pkt
         :  NFToINOutput size
         <- sem_out_pkt_expr;
       RetE
         (STRUCT {
            "fst"
              ::= (STRUCT {
                     "val1"
                       ::= Valid (STRUCT {
                             "tag"  ::= Const ty (natToWord RoutingTagSz IntRegTag);
                             "data" ::= SignExtendTruncLsb Rlen ((#sem_out_pkt) @% "outIN")
                           });
                     "val2"
                       ::= Valid (STRUCT {
                             "tag"  ::= Const ty (natToWord RoutingTagSz FloatCsrTag);
                             "data" ::= (csr (#sem_out_pkt @% "flags") : (Bit Rlen @# ty))
                           });
                     "memBitMask" ::= $$(getDefaultConst (Array Rlen_over_8 Bool));
                     "taken?" ::= $$false;
                     "aq" ::= $$false;
                     "rl" ::= $$false
                   } : ExecContextUpdPkt @# ty);
            "snd" ::= Invalid
          } : PktWithException ExecContextUpdPkt @# ty).

  Definition Float_word
    :  @FUEntry ty
    := {|
         fuName := append "float_word" suffix;
         fuFunc
           := fun sem_in_pkt_expr : NFToINInput expWidthMinus2 sigWidthMinus2 ## ty
                => LETE sem_in_pkt
                     :  NFToINInput expWidthMinus2 sigWidthMinus2
                     <- sem_in_pkt_expr;
                   @NFToIN_expr
                     (32 - 2)
                     expWidthMinus2
                     sigWidthMinus2
                     exp_valid
                     sig_valid
                     ty
                     (#sem_in_pkt);
         fuInsts
           := [
                {|
                  instName   := append "fcvt.w" suffix;
                  extensions := exts;
                  uniqId
                    := [
                         fieldVal fmtField format_field;
                         fieldVal instSizeField ('b"11");
                         fieldVal opcodeField   ('b"10100");
                         fieldVal rs2Field      ('b"00000");
                         fieldVal rs3Field      ('b"11000")
                       ];
                  inputXform  := Float_Int_Input ($$true);
                  outputXform := @Float_Int_Output (32 - 2);
                  optMemXform := None;
                  instHints   := falseHints<|hasFrs1 := true|><|hasRd := true|> 
                |};
                {|
                  instName   := append "fcvt.wu" suffix;
                  extensions := exts;
                  uniqId
                    := [
                         fieldVal fmtField format_field;
                         fieldVal instSizeField ('b"11");
                         fieldVal opcodeField   ('b"10100");
                         fieldVal rs2Field      ('b"00001");
                         fieldVal rs3Field      ('b"11000")
                       ];
                  inputXform  := Float_Int_Input ($$false);
                  outputXform := @Float_Int_Output (32 - 2);
                  optMemXform := None;
                  instHints   := falseHints<|hasFrs1 := true|><|hasRd := true|> 
                |}
              ]
      |}.

  Definition Float_long
    :  @FUEntry ty
    := {|
         fuName := append "float_long" suffix;
         fuFunc
           := fun sem_in_pkt_expr : NFToINInput expWidthMinus2 sigWidthMinus2 ## ty
                => LETE sem_in_pkt
                     :  NFToINInput expWidthMinus2 sigWidthMinus2
                     <- sem_in_pkt_expr;
                   @NFToIN_expr
                     (64 - 2)
                     expWidthMinus2
                     sigWidthMinus2
                     exp_valid
                     sig_valid
                     ty
                     (#sem_in_pkt);
         fuInsts
           := [
                {|
                  instName   := append "fcvt.l" suffix;
                  extensions := exts;
                  uniqId
                    := [
                         fieldVal fmtField format_field;
                         fieldVal instSizeField ('b"11");
                         fieldVal opcodeField   ('b"10100");
                         fieldVal rs2Field      ('b"00010");
                         fieldVal rs3Field      ('b"11000")
                       ];
                  inputXform  := Float_Int_Input ($$true);
                  outputXform := @Float_Int_Output (64 - 2);
                  optMemXform := None;
                  instHints   := falseHints<|hasFrs1 := true|><|hasRd := true|> 
                |};
                {|
                  instName   := append "fcvt.lu" suffix;
                  extensions := exts;
                  uniqId
                    := [
                         fieldVal fmtField format_field;
                         fieldVal instSizeField ('b"11");
                         fieldVal opcodeField   ('b"10100");
                         fieldVal rs2Field      ('b"00011");
                         fieldVal rs3Field      ('b"11000")
                       ];
                  inputXform  := Float_Int_Input ($$false);
                  outputXform := @Float_Int_Output (64 - 2);
                  optMemXform := None;
                  instHints   := falseHints<|hasFrs1 := true|><|hasRd := true|> 
                |}
              ]
      |}.

  Definition Int_float_Output (sem_out_pkt_expr : OpOutput expWidthMinus2 sigWidthMinus2 ## ty)
    :  PktWithException ExecContextUpdPkt ## ty
    := LETE sem_out_pkt
         :  OpOutput expWidthMinus2 sigWidthMinus2
         <- sem_out_pkt_expr;
       RetE
         (STRUCT {
            "fst"
              ::= (STRUCT {
                     "val1"
                       ::= Valid (STRUCT {
                             "tag"  ::= Const ty (natToWord RoutingTagSz FloatRegTag);
                             "data"
                               ::= OneExtendTruncLsb Rlen
                                     (NFToBit
                                        ((#sem_out_pkt @% "out") : NF expWidthMinus2 sigWidthMinus2 @# ty)
                                      : Bit len @# ty)
                                 });
                     "val2"
                       ::= Valid (STRUCT {
                             "tag"  ::= Const ty (natToWord RoutingTagSz FloatCsrTag);
                             "data" ::= (csr (#sem_out_pkt @% "exceptionFlags") : (Bit Rlen @# ty)) 
                           });
                     "memBitMask" ::= $$(getDefaultConst (Array Rlen_over_8 Bool));
                     "taken?" ::= $$false;
                     "aq" ::= $$false;
                     "rl" ::= $$false
                   } : ExecContextUpdPkt @# ty);
            "snd" ::= Invalid
          } : PktWithException ExecContextUpdPkt @# ty).

  Definition Word_float
    :  @FUEntry ty
    := {|
         fuName := append "word_float" suffix;
         fuFunc
           := fun sem_in_pkt_expr : INToNFInput (32 - 2) ## ty
                => LETE sem_in_pkt
                     :  INToNFInput (32 - 2)
                     <- sem_in_pkt_expr;
                  INToNF_expr
                    expWidthMinus2
                    sigWidthMinus2
                    (#sem_in_pkt);
         fuInsts
           := [
                {|
                  instName   := append (append "fcvt" suffix) ".w";
                  extensions := exts_32;
                  uniqId
                    := [
                         fieldVal fmtField format_field;
                         fieldVal instSizeField ('b"11");
                         fieldVal opcodeField   ('b"10100");
                         fieldVal rs2Field      ('b"00000");
                         fieldVal rs3Field      ('b"11010")
                       ];
                  inputXform 
                    := fun context_pkt_expr : ExecContextPkt ## ty
                       => LETE context_pkt
                            <- context_pkt_expr;
                          RetE
                            (STRUCT {
                               "in"            ::= ZeroExtendTruncLsb ((32 - 2) + 1 + 1) (#context_pkt @% "reg1");
                               "signedIn"      ::= $$true;
                               "afterRounding" ::= $$true;
                               "roundingMode" ::= rounding_mode (#context_pkt)
                             } : INToNFInput (32 - 2) @# ty);
                  outputXform := Int_float_Output;
                  optMemXform := None;
                  instHints   := falseHints<|hasRs1 := true|><|hasFrd := true|> 
                |};
                {|
                  instName   := append (append "fcvt" suffix) ".wu";
                  extensions := exts_32;
                  uniqId
                    := [
                         fieldVal fmtField format_field;
                         fieldVal instSizeField ('b"11");
                         fieldVal opcodeField   ('b"10100");
                         fieldVal rs2Field      ('b"00001");
                         fieldVal rs3Field      ('b"11010")
                       ];
                  inputXform 
                    := fun context_pkt_expr : ExecContextPkt ## ty
                         => LETE context_pkt
                              <- context_pkt_expr;
                            RetE
                              (STRUCT {
                                 "in"            ::= ZeroExtendTruncLsb ((32 - 2) + 1 + 1) (#context_pkt @% "reg1");
                                 "signedIn"      ::= $$false;
                                 "afterRounding" ::= $$true;
                                 "roundingMode" ::= rounding_mode (#context_pkt)
                               } : INToNFInput (32 - 2) @# ty);
                  outputXform := Int_float_Output;
                  optMemXform := None;
                  instHints   := falseHints<|hasRs1 := true|><|hasFrd := true|> 
                |}
             ]
      |}.

  Definition Long_float
    :  @FUEntry ty
    := {|
         fuName := append "long_float" suffix;
         fuFunc
           := fun sem_in_pkt_expr : INToNFInput (64 - 2) ## ty
                => LETE sem_in_pkt
                     :  INToNFInput (64 - 2)
                     <- sem_in_pkt_expr;
                  INToNF_expr
                    expWidthMinus2
                    sigWidthMinus2
                    (#sem_in_pkt);
         fuInsts
           := [
                {|
                  instName   := append (append "fcvt" suffix) ".l";
                  extensions := exts_64;
                  uniqId
                    := [
                         fieldVal fmtField format_field;
                         fieldVal instSizeField ('b"11");
                         fieldVal opcodeField   ('b"10100");
                         fieldVal rs2Field      ('b"00010");
                         fieldVal rs3Field      ('b"11010")
                       ];
                  inputXform 
                    := fun context_pkt_expr : ExecContextPkt ## ty
                         => LETE context_pkt
                              <- context_pkt_expr;
                            RetE
                              (STRUCT {
                                 "in"            ::= ZeroExtendTruncLsb ((64 - 2) + 1 + 1) (#context_pkt @% "reg1");
                                 "signedIn"      ::= $$true;
                                 "afterRounding" ::= $$true;
                                 "roundingMode" ::= rounding_mode (#context_pkt)
                               } : INToNFInput (64 - 2) @# ty);
                  outputXform := Int_float_Output;
                  optMemXform := None;
                  instHints   := falseHints<|hasRs1 := true|><|hasFrd := true|> 
                |};
                {|
                  instName   := append (append "fcvt" suffix) ".lu";
                  extensions := exts_64;
                  uniqId
                    := [
                         fieldVal fmtField format_field;
                         fieldVal instSizeField ('b"11");
                         fieldVal opcodeField   ('b"10100");
                         fieldVal rs2Field      ('b"00011");
                         fieldVal rs3Field      ('b"11010")
                       ];
                  inputXform 
                    := fun context_pkt_expr : ExecContextPkt ## ty
                         => LETE context_pkt
                              <- context_pkt_expr;
                            RetE
                              (STRUCT {
                                 "in"            ::= ZeroExtendTruncLsb ((64 - 2) + 1 + 1) (#context_pkt @% "reg1");
                                 "signedIn"      ::= $$false;
                                 "afterRounding" ::= $$true;
                                 "roundingMode" ::= rounding_mode (#context_pkt)
                               } : INToNFInput (64 - 2) @# ty);
                  outputXform := Int_float_Output;
                  optMemXform := None;
                  instHints   := falseHints<|hasRs1 := true|><|hasFrd := true|> 
                |}
             ]
      |}.

  Close Scope kami_expr.

End Fpu.
