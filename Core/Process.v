From mathcomp.ssreflect
Require Import ssreflect ssrbool ssrnat eqtype ssrfun seq.
From mathcomp
Require Import path.
Require Import Eqdep.
Require Import Relation_Operators.
From DiSeL.Heaps
Require Import pred prelude idynamic ordtype finmap pcm unionmap heap coding.
From DiSeL.Core
Require Import Freshness State EqTypeX DepMaps Protocols Worlds NetworkSem.
From DiSeL.Core
Require Import Actions Injection InductiveInv.

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.
Variable lock : Type.

Section ProcessSyntax.

Variable this_node : nid.

(* Syntax for process *)
Inductive proc (W : world) A :=
  Unfinished | Ret of A | Act of action W A this_node |
  Seq B of proc W B & B -> proc W A |
  Par B C of proc W B & proc W C & (B * C) -> proc W A |
  Inject V K of injects V W K & proc V A |
  WithLock of lock & proc W A |
  WithInv p I (ii : InductiveInv p I) of
          W = mkWorld (ProtocolWithIndInv ii) & proc (mkWorld p) A. 

Definition pcat W A B (t : proc W A) (k : A -> Pred (proc W B)) :=
  [Pred s | exists q, s = Seq t q /\ forall x, q x \In k x].

Inductive schedule :=
  ActStep | SeqRet | SeqStep of schedule |
  ParRet | ParStepL of schedule | ParStepR of schedule |
  InjectStep of schedule | InjectRet |
  WithLockStep of schedule | WithLockRet |
  WithInvStep of schedule | WithInvRet.

End ProcessSyntax.

Implicit Arguments Unfinished [this_node W A].
Implicit Arguments Ret [this_node W A].
Implicit Arguments Act [this_node W A].
Implicit Arguments Seq [this_node W A B].
Implicit Arguments Par [this_node W A B C].
Implicit Arguments WithLock [this_node W A].
Implicit Arguments WithInv [this_node W A].

Section ProcessSemantics.

Variable this_node : nid.

Fixpoint step (W : world) A (s1 : state) (p1 : proc this_node W A)
         sc (s2 : state) (p2 : proc this_node W A) : Prop :=
  match sc, p1 with
  (* Action - make a step *)  
  | ActStep, Act a => exists v pf, @a_step _ _ _ a s1 pf s2 v /\ p2 = Ret v
  (* Sequencing - apply a continuation *)  
  | SeqRet, Seq _ (Ret v) k => s2 = s1 /\ p2 = k v
  | SeqStep sc', Seq _ p' k1 => 
    exists p'', step s1 p' sc' s2 p'' /\ p2 = Seq p'' k1
  (* Parallel Execution *)
  | ParRet, Par _ _ (Ret vb) (Ret vc) k => s2 = s1 /\ p2 = k (vb, vc)
  | ParStepL sc', Par _ _ pl pr k =>
    exists pl', step s1 pl sc' s2 pl' /\ p2 = Par pl' pr k
  | ParStepR sc', Par _ _ pl pr k =>
    exists pr', step s1 pr sc' s2 pr' /\ p2 = Par pl pr' k
  (* CSL Style Locks *)
  | WithLockRet, WithLock _ (Ret v) =>
    [/\ s2 = s1 & p2 = Ret v]
  | WithLockStep sc', WithLock l p' =>
    exists p'', step s1 p' sc' s2 p'' /\ p2 = WithLock l p''
  (* Injection of a non-reduced term *)
  | InjectRet, Inject V K pf (Ret v) =>
     exists s1', [/\ s2 = s1, p2 = Ret v & extends pf s1 s1']
  | InjectStep sc', Inject V K pf t1' =>
    exists s1' s2' s t2', 
    [/\ p2 = Inject pf t2', s1 = s1' \+ s, s2 = s2' \+ s, 
     s1' \In Coh V & step s1' t1' sc' s2' t2']
  (* Imposing an inductive invariant on a non-reduced term *)
  | WithInvRet, WithInv p inv ii pf (Ret v) =>
     exists s1', [/\ s2 = s1, p2 = Ret v & s1 = s1']
  | WithInvStep sc', WithInv p inv ii pf t1' =>
    exists t2', p2 = WithInv p inv ii pf t2' /\  
                     step s1 t1' sc' s2 t2'   
  | _, _ => False
  end.

Fixpoint good (W : world) A (p : proc this_node W A) sc  : Prop :=
  match sc, p with
  | ActStep, Act _ => True
  | SeqRet, Seq _ (Ret _) _ => True
  | SeqStep sc', Seq _ p' _ => good p' sc'
  | ParRet, Par _ _ (Ret _) (Ret _) _ => true
  | ParStepL sc', Par _ _ pl _ _ => good pl sc'
  | ParStepR sc', Par _ _ _ pr _ => good pr sc'
  | WithLockRet, WithLock _ (Ret _) => True
  | WithLockStep sc', WithLock _ p => good p sc'
  | InjectStep sc', Inject _ _ _ p' => good p' sc'
  | InjectRet, Inject _ _ _ (Ret _) => True
  | WithInvStep sc', WithInv _ _ _ _ p' => good p' sc'
  | WithInvRet, WithInv _ _ _ _ (Ret _) => True
  | _, _ => False
  end.

(*

[Safety in small-step semantics]

The safety (in order to make the following step) with respect to the
schedule is defined inductively on the shape of the program and the
schedule. Omitting the schedule is not a good idea, at it's required
in order to "sequentialize" the execution of the program
structure. Once it's dropped, this_node structure is lost.

 *)

Fixpoint safe (W : world) A (p : proc this_node W A) sc (s : state)  : Prop :=
  match sc, p with
  | ActStep, Act a => a_safe a s
  | SeqRet, Seq _ (Ret _) _ => True
  | SeqStep sc', Seq _ p' _ => safe p' sc' s
  | ParRet, Par _ _ (Ret _) (Ret _) _ => True
  | ParStepL sc', Par _ _ pl _ _ => safe pl sc' s
  | ParStepR sc', Par _ _ _ pr _ => safe pr sc' s
  | WithLockRet, WithLock _ (Ret _) => True
  | WithLockStep sc', WithLock _ p => safe p sc' s
  | InjectStep sc', Inject V K pf p' =>
      exists s', extends pf s s' /\ safe p' sc' s'
  | InjectRet, Inject V K pf (Ret _) => exists s', extends pf s s'
  | WithInvStep sc', WithInv _ _ _ _ p' => safe p' sc' s
  | WithInvRet, WithInv _ _ _ _ (Ret _) => True
  | _, _ => True
  end.

Definition pstep (W : world) A s1 (p1 : proc this_node W A) sc s2 p2 := 
  [/\ s1 \In Coh W, safe p1 sc s1 & step s1 p1 sc s2 p2].

(* Some sanity lemmas wrt. stepping *)

Lemma pstep_safe (W : world) A s1 (t : proc this_node W A) sc s2 q : 
        pstep s1 t sc s2 q -> safe t sc s1.
Proof. by case. Qed.


(*

The following lemma established the operational "progress" property: a
program, which is safe and also the schedule is appropriate. Together,
this_node implies that we can do a step. 
 *)

Lemma proc_progress W A s (p : proc this_node W A) sc : 
        s \In Coh W -> safe p sc s -> good p sc ->  
        exists s' (p' : proc this_node W A), pstep s p sc s' p'.
Proof.
move=>C H1 H2; elim: sc W A s p H2 H1 C=>[||sc IH||sc IH|sc IH|sc IH||sc IH||sc IH|]W A s. 
- case=>//=a _/= H; move/a_step_total: (H)=>[s'][r]H'.
  by exists s', (Ret r); split=>//=; exists r, H.  
- by case=>//; move=>B p k/=; case: p=>//b _ _; exists s, (k b). 
- case=>//B p k/=H1 H2 C.
  case: (IH W B s p H1 H2 C)=>s'[p'][G1 G2].
  by exists s', (Seq p' k); split=>//; exists p'.
- case=>//=.
  move=>B C pB pC k//.
  case pB=>//b.
  case pC=>//c H1 H2 HC.
  by exists s, (k (b, c)).
- case=>// B C pB pC k/= Hgood Hsafe Hcoh.
  case: (IH W B s pB Hgood Hsafe Hcoh)=> s' [pB']HstepB'.
  exists s', (Par pB' pC k).
  split=>//=.
  exists pB'.
  split=>//=.
  apply HstepB'.
- case=>// B C pB pC k/= Hgood Hsafe Hcoh.
  case: (IH W C s pC Hgood Hsafe Hcoh)=> s' [pC']HstepC'.
  exists s', (Par pB pC' k).
  split=>//=.
  exists pC'.
  split=>//=.
  apply HstepC'.
- case=>// V K pf p/=H1 [z][E]H2 C.
  case: (E)=>s3[Z] C1 C2.
  case: (IH V A z p H1 H2 C1) =>s'[p']H3; case: H3=>S St.
  exists (s' \+ s3), (Inject pf p'); split=>//; first by exists z.  
  by subst s; exists z, s', s3, p'. 
- case=>//V K pf; case=>// v/=_[s'] E C.          
  by exists s, (Ret v); split=>//=; exists s'.
- case=>// l p /= Hgood Hsafe Hcoh.
  case: (IH W A s p Hgood Hsafe Hcoh) => s'[p']Hstep.
  exists s', (WithLock l p').
  split=>//=.
  exists p'.
  split.
  apply Hstep.
  reflexivity.
- case=>//l; case=>// v /=_ _ Hcoh.
  exists s, (Ret v).
  split=>//.
  
- case=>//pr I ii E p/= H1 H2 C.
  have C' : s \In Coh (mkWorld pr) by subst W; apply: (with_inv_coh C). 
  case: (IH (mkWorld pr) A s p H1 H2 C')=>s'[p']H3.
  exists s', (WithInv pr I ii E p'); split=>//=.
  by exists p'; split=>//; case: H3.
- case=>//pr I ii E; case=>//v/=_ _ C.          
  by exists s, (Ret v); split=>//=; exists s. 
Qed.

(* Some view lemmas for processes and corresponding schedules *)

Lemma stepUnfin W A s1 sc s2 (t : proc this_node W A) : 
        pstep s1 Unfinished sc s2 t <-> False.
Proof. by split=>//; case; case: sc. Qed.

Lemma stepRet W A s1 sc s2 (t : proc this_node W A) v : 
        pstep s1 (Ret v) sc s2 t <-> False.
Proof. by split=>//; case; case: sc. Qed.

Lemma stepAct W A s1 a sc s2 (t : proc this_node W A) : 
        pstep s1 (Act a) sc s2 t <->
        exists v pf, [/\ sc = ActStep, t = Ret v & @a_step _ _ _ a s1 pf s2 v].
Proof.
split; first by case=>C; case: sc=>//= c [v [pf [H ->]]]; exists v, pf. 
case=>v[pf] [->-> H]; split=>//; last by exists v, pf.
by apply: (a_safe_coh pf). 
Qed.

Lemma stepSeq W A B s1 (t : proc this_node W B) k sc s2 (q : proc this_node W A) :
  pstep s1 (Seq t k) sc s2 q <->
  (exists v, [/\ sc = SeqRet, t = Ret v, q = k v, s2 = s1 &
    s1 \In Coh W]) \/
  exists sc' p',
    [/\ sc = SeqStep sc', q = Seq p' k & pstep s1 t sc' s2 p'].
Proof.
split; last first.
- case; first by case=>v [->->->->]. 
  by case=>sc' [t'][->->][S H]; do !split=>//; exists t'. 
- case; case: sc=>//[|sc] C. 
  + by case: t=>//= v _ [->->]; left; exists v. 
  + by move=>G /= [p' [H1 ->]]; right; exists sc, p'.
Qed.

Lemma stepPar W A B C pB pC (k : B * C -> proc this_node W A) sc s1 s2 q : 
  pstep s1 (Par pB pC k) sc s2 q <->
  (exists b c, [/\ sc = ParRet, pB = Ret b, pC = Ret c, q = k (b, c), s2 = s1 & s1 \In Coh W]) \/
  (exists sc' pB', [/\ sc = ParStepL sc', q = Par pB' pC k & pstep s1 pB sc' s2 pB']) \/
  (exists sc' pC', [/\ sc = ParStepR sc', q = Par pB pC' k & pstep s1 pC sc' s2 pC']).
Proof.  
  split; last first.
  - case.
    + by case=> b [c][->->->->->]Hcoh; split=>//.
    + case. case=> sc' [pB'][->->]. case=>//Hcoh Hsafe Hstep.
      split; first by assumption.
      assumption.
      by exists pB'; split.
    + case=> sc' [pB'][->->]. case=>//.
      intros.
      split; first by assumption.
      assumption.
      by exists pB'; split.
  - case. case: sc=>//[|sc|sc] Hcoh.
    + case: pB=>//=b; case pC=>//=c _ [->->].
      by left; exists b, c.
    + move=> Hsafe/= [pB' [H1 ->]].
      by right; left; exists sc, pB'.
    + move=> Hsafe/= [pC' [H1 ->]].
      by right; right; exists sc, pC'.
Qed.

Lemma stepWithLock W A l (p : proc this_node W A) sc s1 s2 q :
  pstep s1 (WithLock l p) sc s2 q <->
  (exists v, [/\ sc = WithLockRet, p = Ret v, q = (Ret v), s2 = s1 & s1 \In Coh W]) \/
  (exists sc' p', [/\ sc = WithLockStep sc', q = WithLock l p' & pstep s1 p sc' s2 p']).
Proof.
  split; last first.
  - case.
    + case=> v[->->->->] H2.
      split; by try assumption.
    + case=> sc'[p'][->->]. case=>//Hcoh Hsafe Hstep.
      split; try assumption.
      by exists p'.
  - case. case: sc=>//[sc|] Hcoh.
    
      
Lemma stepInject V W K A (em : injects V W K)
      s1 (t : proc this_node V A) sc s2 (q : proc this_node W A) :
  pstep s1 (Inject em t) sc s2 q <->
  (* Case 1 : stepped to the final state s1' of the inner program*)
  (exists s1' v, [/\ sc = InjectRet, t = Ret v, q = Ret v, s2 = s1 &
                     extends em s1 s1']) \/
  (* Case 2 : stepped to the nextx state s12 of the inner program*)
  exists sc' t' s1' s2' s, 
    [/\ sc = InjectStep sc', q = Inject em t', 
     s1 = s1' \+ s, s2 = s2' \+ s, s1 \In Coh W &
              pstep s1' t sc' s2' t'].
Proof.
split; last first.
- case.
  + case=>s1' [v][->->->->] E.
    split=>//=; [by case: E=>x[] | by exists s1'|by exists s1'].
  case=>sc' [t'][s1'][s2'][s][->->->-> C][[C' S] T]. 
  split=>//=; last by exists s1', s2', s, t'. 
  by exists s1'; split=>//; exists s. 
case=>C; case: sc=>//=; last first.
- case: t=>//= v [C1 S][s1'][->->{s2 q}] X.
  by left; exists s1'; exists v. 
move=>sc /= [s'][X] S [s1'][s2'][t'][t2'][??? C1'] T; subst q s1 s2. 
right; exists sc, t2', s1', s2', t'; do !split=>//.
by case: X=>t'' [E] Cs' _; rewrite (coh_prec (cohS C) E _ Cs'). 
Qed.

Lemma stepWithInv W A pr I (ii : InductiveInv pr I) s1 
      (t : proc this_node (mkWorld pr) A) sc s2 (q : proc this_node W A) pf :
  pstep s1 (WithInv pr I ii pf t) sc s2 q <-> 
  (exists v, [/\ sc = WithInvRet, t = Ret v, q = Ret v, s2 = s1,
                 s1 \In Coh W & W = mkWorld (ProtocolWithIndInv ii)]) \/
  exists sc' t' , [/\ sc = WithInvStep sc', q = WithInv pr I ii pf t',
                      W = mkWorld (ProtocolWithIndInv ii),
                      s1 \In Coh W & pstep s1 t sc' s2 t'].
Proof.
split; last first.
- case.
  + by case=>v[->->->->{s2}]C E; split=>//=; exists s1.
   by case=>sc' [t'][->->{sc q}]E C[C' S]T; split=>//=; exists t'.   
case=>C; case: sc=>//=; last first.
- by case: t=>//=v _[s1'][Z1]Z2 Z3; subst s2 s1' q; left; exists v. 
move=>sc /=S[t'][->{q}T]; right; exists sc, t'; split=>//.
by split=>//; subst W; apply: (with_inv_coh C).
Qed.

(*

[Stepping and network semantics]

The following lemma ensures that the operational semantics of our
programs respect the global network semantics.

 *)

Lemma pstep_network_sem (W : world) A s1 (t : proc this_node W A) sc s2 q :
        pstep s1 t sc s2 q -> network_step W this_node s1 s2.
Proof.
elim: sc W A s1 s2 t q=>/=.
- move=>W A s1 s2 p q; case: p; do?[by case|by move=>?; case].
  + by move=>a/stepAct [v][pf][Z1]Z2 H; subst q; apply: (a_step_sem H).
  + by move=>???; case. 
  + by move=>?????; case.
  + by move=>????; case.
  by move=>?????; case.   
- move=>W A s1 s2 p q; case: p; do?[by case|by move=>?; case].
  + move=>B p p0/stepSeq; case=>[[v][_]??? C|[sc'][p'][]]//.
    by subst p s2; apply: Idle.
    intros.
    inversion H.
    inversion H2.
      by move=>????/stepInject; case=>[[?][?][?]|[?][?][?][?][?][?]]//.
   by move=>?????; case.   
- move=>sc HI W A s1 s2 p q; case: p; do?[by case|by move=>?; case].
  + move=>B p p0/stepSeq; case=>[[?][?]|[sc'][p'][][]? ?]//.
    by subst sc' q; apply: HI.
  by move=>?????; case=>? _.
  move=>???? Hyp.  inversion Hyp. inversion H1. 
  move=>????? Hyp.  inversion Hyp. inversion H1.
- move=>W A s1 s2 p q; case: p; do?[by case| by move=>?; case].
  + by move=>???; case.
  + move=>B C pB pC k /stepPar.
    case.
    * move=>[b][c][_]??? -> ?.
      by apply: Idle.
    * case; by move=>[?][?][?].
  + by move=>????; case.
  + by move=>?????; case.
- move=>sc HI W A s1 s2 p q; case: p; do?[by case|by move=>?; case].
  + by move=>???; case.
  + move=> B C pB pC k /stepPar; case.
    * by move=>[?][?][?].
    * case; first last.
      - by move=>[?][?][?].
      - move=>[sc'][pB'][[<-]][H].
        apply HI.
  + by move=>????; case.
  + by move=>?????; case.
- move=>sc HI W A s1 s2 p q; case: p; do?[by case|by move=>?; case].
  + by move=>???; case.
  + move=> B C pB pC k /stepPar; case.
    * by move=>[?][?][?].
    * case.
      - by move=>[?][?][?].
      - move=>[sc'][pB'][[<-]][H].
        apply HI.
  + by move=>????; case.
  + by move=>?????; case.
- move=>sc HI W A s1 s2 p q; case: p; do?[by case|by move=>?; case].
  + by move=>B p p0; case.
  + by move=>?????; case.
  move=>V K pf p/stepInject; case=>[[?][?][?]|[sc'][t'][s1'][s2'][s][][]????]//. 
  subst sc' q s1 s2=>C; move/HI=>S; apply: (sem_extend pf)=>//.
  apply/(cohE pf); exists s2', s; case: (step_coh S)=>C1 C2; split=>//.
  move/(cohE pf): (C)=>[s1][s2][E]C' H.
  by move: (coh_prec (cohS C) E C1 C')=>Z; subst s1'; rewrite (joinfK (cohS C) E). 
  by move=>?????; case.   
- move=>W A s1 s2 p q; case: p; do?[by case|by move=>?; case].
  + by move=>???; case.
  + by move=>?????; case.
  + move=>V K i p; case/stepInject=>[[s1'][v][_]??? X|[?][?][?][?][?][?]]//.
    by subst p q s2; apply: Idle; split=>//; case: X=>x []. 
  by move=>?????; case.

- move=>sc HI W A s1 s2 p q; case: p;
          do?[by case|by move=>?; case|by move=>???; case|by move=>????; case].
  by move=>?????; case.
  move=>pr I ii E p; case/(stepWithInv s1); first by case=>?; case.
  case=>sc'[t'][][]Z1 Z2 _ C1; subst q sc'.
  by move/HI=>T; subst W; apply: with_inv_step. 
move=>W A s1 s2 t q; do?[by case|by move=>?; case|by move=>???; case].
case=>C; case: t=>//pr I ii E; case=>//=v _[s1'][Z1]Z2 Z3.
by subst s1' s2 q; apply: Idle. 
Qed.

(*

[Inductive invariants and stepping]

The following lemma is the crux of wrapping into inductive invariants, as 
it leverages the proof of the fact that each transition preserves the invariant.

*)

Lemma pstep_inv A pr I (ii : InductiveInv pr I) s1 s2 sc
      (t t' : proc this_node (mkWorld pr) A):
  s1 \In Coh (mkWorld (ProtocolWithIndInv ii)) ->
  pstep s1 t sc s2 t' -> 
  s2 \In Coh (mkWorld (ProtocolWithIndInv ii)).
Proof. by move=>C1; case/pstep_network_sem/(with_inv_step C1)/step_coh. Qed.

End ProcessSemantics.
