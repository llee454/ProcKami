Require Import Kami.All RecordUpdate.RecordSet.

Inductive InstSize := Compressed | Normal.

Definition Extensions := STRUCT {
                             "RV32I"    :: Bool ;
                             "RV64I"    :: Bool ;
                             "Zifencei" :: Bool ;
                             "Zicsr"    :: Bool ;
                             "RV32M"    :: Bool ;
                             "RV64M"    :: Bool ;
                             "RV32A"    :: Bool ;
                             "RV64A"    :: Bool ;
                             "RV32F"    :: Bool ;
                             "RV64F"    :: Bool ;
                             "RV32D"    :: Bool ;
                             "RV64D"    :: Bool ;
                             "RV32C"    :: Bool ;
                             "RV64C"    :: Bool }.

Definition UniqId := (list {x: (nat * nat) & word (fst x + 1 - snd x)})%type.

Section Params.
  Variable Xlen_over_8: nat.

  Local Notation Xlen := (8 * Xlen_over_8).
  Local Notation Data := (Bit Xlen).
  Local Notation VAddr := (Bit Xlen).
  Local Notation DataMask := (Bit Xlen_over_8).

  Definition PrivMode := (Bit 2).

  Definition InstSz := 32.
  Definition Inst := (Bit InstSz).

  Definition Exception := (Bit 4).

  Definition InstAddrMisaligned := 0.
  Definition InstAccessFault    := 1.
  Definition IllegalInst        := 2.
  Definition Breakpoint         := 3.
  Definition LoadAddrMisaligned := 4.
  Definition LocalAccessFault   := 5.
  Definition SAmoAddrMisaligned := 6.
  Definition SAmoAccessFault    := 7.
  Definition ECallU             := 8.
  Definition ECallS             := 9.
  Definition ECallH             := 10.
  Definition ECallM             := 11.
  Definition InstPageFault      := 12.
  Definition LoadPageFault      := 13.
  Definition SAmoPageFault      := 15.

  Definition MemOp :=
    STRUCT { "sub_opcode" :: Bit 2 ;
             "funct3"     :: Bit 3 ;
             "funct5"     :: Bit 5 }.

  Section Fields.
    Definition instSizeField := (1, 0).
    Definition opcodeField := (6, 2).
    Definition funct3Field := (14,12).
    Definition funct7Field := (31,25).
    Definition funct6Field := (31,26).
    Definition funct5Field := (31,27).
    Definition rs1Field := (19,15).
    Definition rs2Field := (24,20).
    Definition rdField := (11,7).
    Definition immField := (31,20).
    
    Variable ty: Kind -> Type.
    Variable inst: Inst @# ty.
    
    Local Open Scope kami_expr.
    Definition instSize := inst$[fst instSizeField: snd instSizeField].
    Definition opcode := inst$[fst opcodeField: snd opcodeField].
    Definition funct3 := inst$[fst funct3Field: snd funct3Field].
    Definition funct7 := inst$[fst funct7Field: snd funct7Field].
    Definition funct6 := inst$[fst funct6Field: snd funct6Field].
    Definition funct5 := inst$[fst funct5Field: snd funct5Field].
    Definition rs1 := inst$[fst rs1Field: snd rs1Field].
    Definition rs2 := inst$[fst rs2Field: snd rs2Field].
    Definition rd := inst$[fst rdField: snd rdField].
    Definition imm := inst$[fst immField: snd immField].
    Definition mem_sub_opcode := {< (inst$[5:5]), (inst$[3:3])>}.
    Local Close Scope kami_expr.
  End Fields.

  Definition ExecContextPkt :=
    STRUCT { "pc"                       :: VAddr ;
             "reg1"                     :: Data ;
             "reg2"                     :: Data ;
             "freg1"                    :: Data ;
             "freg2"                    :: Data ;
             "freg3"                    :: Data ;
             "csr"                      :: Data ;
             "inst"                     :: Inst ;
             "instMisalignedException?" :: Bool ;
             "memMisalignedException?"  :: Bool ;
             "mode"                     :: PrivMode ;
             "compressed?"              :: Bool }.

  Definition RoutingTagSz := 3.
  Definition RoutingTag := Bit RoutingTagSz.

  Definition PcTag := 0.
  Definition IntRegTag := 1.
  Definition FloatRegTag := 2.
  Definition CsrTag := 3.
  Definition MemDataTag := 4.
  Definition MemAddrTag := 5.

  Definition RoutedReg := STRUCT { "tag" :: RoutingTag ; "data" :: Data }.

  Definition ExecContextUpdPkt :=
    STRUCT { "val1"       :: Maybe RoutedReg ;
             "val2"       :: Maybe RoutedReg ;
             "memOp"      :: MemOp ;
             "memBitMask" :: DataMask ;
             "taken?"     :: Bool ;
             "exception"  :: Maybe Exception }.

  Section Ty.
    Context {ty: Kind -> Type}.

    Local Open Scope kami_expr.

    Definition LoadOp funct3Val : MemOp @# ty := STRUCT { "sub_opcode" ::= $$ (2'b"00") ;
                                                          "funct3"     ::= funct3Val ;
                                                          "funct5"     ::= $0
                                                     }.
    
    Definition StoreOp funct3Val : MemOp @# ty := STRUCT { "sub_opcode" ::= $$ (2'b"10") ;
                                                           "funct3"     ::= funct3Val ;
                                                           "funct5"     ::= $0
                                                         }.
    
    Definition AmoOp funct3Val funct5Val : MemOp @# ty := STRUCT { "sub_opcode" ::= $$ (2'b"11") ;
                                                                   "funct3"     ::= funct3Val ;
                                                                   "funct5"     ::= funct5Val
                                                                 }.

    Definition noUpdPkt: ExecContextUpdPkt @# ty :=
      (STRUCT { "val1" ::= @Invalid ty _ ;
                "val2" ::= @Invalid ty _ ;
                "memOp" ::= $$ (getDefaultConst MemOp) ;
                "memBitMask" ::= $$ (getDefaultConst DataMask) ;
                "taken?" ::= $$ false ;
                "exception" ::= Invalid }).
    
    Local Close Scope kami_expr.

    Definition MemoryInput := STRUCT {
                                  "mem" :: Data ;
                                  "reg" :: Data }.

    Definition MaskedMem := STRUCT {
                                "data" :: Data ;
                                "mask" :: Array Xlen_over_8 Bool }.
    
    Definition MemoryOutput := STRUCT {
                                   "mem" :: Maybe MaskedMem ;
                                   "reg" :: Maybe Data }.
    
    Record InstHints :=
      { hasRs1      : bool ;
        hasRs2      : bool ;
        hasRd       : bool ;
        hasFrs1     : bool ;
        hasFrs2     : bool ;
        hasFrd      : bool ;
        isBranch    : bool ;
        isJumpImm   : bool ;
        isJumpReg   : bool ;
        isSystem    : bool ;
        isCsr       : bool }.

    Global Instance etaX : Settable _ :=
      mkSettable
        (pure Build_InstHints
              <*> hasRs1 <*> hasRs2 <*> hasRd <*> hasFrs1 <*> hasFrs2 <*> hasFrd
              <*> isBranch <*> isJumpImm <*> isJumpReg <*> isSystem <*> isCsr).

    Definition falseHints :=
      {| hasRs1      := false ;
         hasRs2      := false ;
         hasRd       := false ;
         hasFrs1     := false ;
         hasFrs2     := false ;
         hasFrd      := false ;
         isBranch    := false ;
         isJumpImm   := false ;
         isJumpReg   := false ;
         isSystem    := false ;
         isCsr       := false |}.

    Record InstEntry ik ok :=
      { instName     : string ;
        extensions   : list string ;
        uniqId       : UniqId ;        
        inputXform   : ExecContextPkt ## ty -> ik ## ty ;
        outputXform  : ok ## ty -> ExecContextUpdPkt ## ty ;
        optMemXform  : option (MemoryInput ## ty -> MemoryOutput ## ty) ;
        instHints    : InstHints }.

    Record FUEntry :=
      { fuName    : string ;
        fuInputK  : Kind ;
        fuOutputK : Kind ;
        fuFunc    : fuInputK ## ty -> fuOutputK ## ty ;
        fuInsts   : list (InstEntry fuInputK fuOutputK) }.
  End Ty.

  Definition fieldVal range value :=
    existT (fun x => word (fst x + 1 - snd x)) range value.

End Params.

Module RecordNotations.
  Notation "x [ proj  :=  v ]" := (set proj (pure v) x)
                                    (at level 14, left associativity).
  Notation "x [ proj  ::=  f ]" := (set proj f x)
                                     (at level 14, f at next level, left associativity).
End RecordNotations.

