/*
 * Copyright 2005 by IDIAP Research Institute
 *                   http://www.idiap.ch
 *
 * See the file COPYING for the licence associated with this software.
 */

%{
#include "stdio.h"
#include "stdlib.h"
#include "string.h"
#include "htkparse.h"

/* function prototypes */
void htkerror( const char *str ) ;
void initHTKDef() ;
void cleanHTKDef() ;
void cleanHMM( HTKHMM *hmm ) ;
void cleanTransMat( HTKTransMat *tm ) ;
void cleanState( HTKHMMState *st ) ;
void cleanMixture( HTKMixture *mix ) ;
void outputGlobalOpts() ;
void outputSharedStates() ;
void outputSharedTransMats() ;
void outputMixturePools() ;
void outputHMM( HTKHMM *hmm ) ;
void outputHMMState( HTKHMMState *state , int is_shared ) ;
void outputTransMat( HTKTransMat *tm , int is_shared ) ;

/* global variables */
HTKDef htk_def ;

/* external functions */
extern int htklex(void *lvalp,void *fd) ;

/* Bison defines to allow a (FILE *) to be passed to yyparse and yylex */
#define YYPARSE_PARAM fileptr
#define YYLEX_PARAM fileptr
%}

%pure_parser

%union {
    real            *fptr ; 
    char            *cptr ;
    real            fval ;
    int             ival ;
    HTKHMM          *hmmptr ;
    HTKHMMList      *hmmlistptr ;
    HTKHMMState     *hmmstateptr ;
    HTKHMMStateList *hmmstatelistptr ;
    HTKMixture      *mixptr ;
    HTKMixturePool  *mixpoolptr ;
    HTKMixtureList  *mixlistptr ;
    HTKTransMat     *transmatptr ;
    RealVector      *rvecptr ;
    IntVector       *ivecptr ;
    CovKind         ckind ;
    DurKind         dkind ;
}

%token <ival> TRANSP VECSIZE STREAMINFO NUMSTATES STATE NUMMIXES MIXTURE MEAN VARIANCE INTEGER
%token <cptr> PARMKIND HMMSETID HMACRO SMACRO MMACRO TMACRO VMACRO STRING QUOTEDSTRING TMIX
%token <fval> GCONST REAL

%type <hmmptr> hmmdef
%type <transmatptr> transp transmatdef shtransmatdef
%type <hmmstateptr> statedef shstatedef
%type <hmmstatelistptr> states
%type <mixptr> mixturedef mixpdf
%type <mixlistptr> mixtures mixturelist
%type <rvecptr> rvector meanvec variancevec
%type <ivecptr> ivector
%type <fval> gconst
%type <ckind> covkind
%type <dkind> durkind

%token BEGINHMM ENDHMM OMACRO 
%token DIAGC INVDIAGC FULLC LLTC XFORMC NULLD POISSOND GAMMAD GEND

%start htkdef


%%

/******* MAIN GRAMMAR ********/

htkdef      :       {
                        initHTKDef() ;
                    }
                    htkmacros
                    {
            				/*
                        int i ;
				
                        outputGlobalOpts() ;
                        outputMixturePools() ;
                        outputSharedStates() ;
                        outputSharedTransMats() ;
                        for ( i=0 ; i<htk_def.n_hmms ; i++ )
                            outputHMM( htk_def.hmms[i] ) ;
								fflush(stdout);
								exit(1);
								*/
                    }
            ;

htkmacros   :       htkmacro
            |       htkmacros htkmacro
            ;

htkmacro    :       globalopts
            |       hmmdef
                    {
                        /* add new hmm def to the list of hmms */
                        htk_def.n_hmms++ ;
                        htk_def.hmms = (HTKHMM **)realloc( htk_def.hmms , htk_def.n_hmms*sizeof(HTKHMM *) ) ;
                        htk_def.hmms[htk_def.n_hmms-1] = $1 ;
                    }
            |       shtransmatdef
                    {
                        /* add new shared transition matrix definition to the list of shared transition matrices */
                        htk_def.n_sh_transmats++ ;
                        htk_def.sh_transmats = (HTKTransMat **)realloc( htk_def.sh_transmats ,
                                                   htk_def.n_sh_transmats * sizeof(HTKTransMat *) ) ;
                        htk_def.sh_transmats[htk_def.n_sh_transmats-1] = $1 ;
                    }
            |       shstatedef
                    {
                        /* add new shared state definition to the list of shared states */
                        htk_def.n_sh_states++ ;
                        htk_def.sh_states = (HTKHMMState **)realloc( htk_def.sh_states ,
                                                  htk_def.n_sh_states * sizeof(HTKHMMState *) ) ;
                        htk_def.sh_states[htk_def.n_sh_states-1] = $1 ;
                    }
            |       VMACRO variancevec
                    {
                        fprintf( stderr , "htkparse: ~v macros not supported - ignoring ~v \"%s\" definition\n" , $1 ) ;
                        free( $1 ) ;
                        if ( $2->elems != NULL )
                        {
                           free( $2->elems ) ;
                        }
                        free( $2 ) ;
                    }
            |       MMACRO meanvec variancevec
                    {
                        /* shared mixture definition */
                        int i , len ;
                        char name[100] ;
                        HTKMixturePool *pool ;
                        HTKMixture *mix ;
                        
                        /* extract the mixture pool name from the macro string */
                        if ( (len = strcspn( $1 , "0123456789" )) == 0 )
                            htkerror("HTKPARSE:htkmacro - MMACRO pool name not found\n") ;
                        strncpy( name , $1 , len*sizeof(char) ) ;
                        name[len] = '\0' ;
                        
                        /* find the mixture pool in our list of mixture pools */
                        for ( i=0 ; i<htk_def.n_mix_pools ; i++ )
                        {
                            if ( strcmp( htk_def.mix_pools[i]->name , name ) == 0 )
                            {
                                /* we found the pool - add this mixture to the pool */
                                pool = htk_def.mix_pools[i] ;
                                break ;
                            }
                        }

                        if ( i >= htk_def.n_mix_pools )
                        {
                            /* pool not found - create a new one */
                            htk_def.n_mix_pools++ ;
                            htk_def.mix_pools = (HTKMixturePool **)realloc( htk_def.mix_pools ,
                                                         htk_def.n_mix_pools * sizeof(HTKMixturePool *) ) ;
                            pool = (HTKMixturePool *)malloc( sizeof(HTKMixturePool) ) ;
                            pool->name = (char *)malloc( (strlen(name)+1)*sizeof(char) ) ;
                            pool->n_mixes = 0 ;
                            pool->mixes = NULL ;
                            strcpy( pool->name , name ) ;
                            htk_def.mix_pools[htk_def.n_mix_pools-1] = pool ;
                        }

                        /* create the new mixture */
                        mix = (HTKMixture *)malloc( sizeof(HTKMixture) ) ;
                        mix->id = atoi( $1+len ) ;
                        mix->weight = 1.0 ;
                        mix->n_means = $2->n_elems ;
                        mix->means = $2->elems ;
                        mix->n_vars = $3->n_elems ;
                        mix->vars = $3->elems ;
                        free( $2 ) ;
                        free( $3 ) ;
                        mix->gconst = 0.0 ;
                        
                        /* add mixture to 'pool' */
                        if ( mix->id != (pool->n_mixes+1) )
                            htkerror("HTKPARSE:htkmacro - shmixdef mix id does not match pool n_mixes\n") ;
                        pool->n_mixes++ ;
                        pool->mixes = (HTKMixture **)realloc( pool->mixes , pool->n_mixes*sizeof(HTKMixture *) ) ;
                        pool->mixes[pool->n_mixes-1] = mix ;

                        free( $1 ) ;
                    }
            ;


/******** GLOBAL OPTIONS GRAMMAR *********/

optglobopts :       /* empty */
            |       globalopts
            ;
            
globalopts  :       OMACRO options
            ;

options     :       option
            |       options option
            ;

option      :       HMMSETID
                    {
                        if ( htk_def.global_opts.hmm_set_id != NULL )
                        {
                            /* we already have a hmm_set_id value - make sure that this one is the same */
                            if ( strcmp( htk_def.global_opts.hmm_set_id , $1 ) != 0 )
                                htkerror("HTKPARSE:option - hmm_set_id mismatch\n") ;
                        }
                        else
                            htk_def.global_opts.hmm_set_id = $1 ;
                    }
            |       STREAMINFO ivector
                    {
                        int i , sum ;
                            
                        /* check that the vector size is correct */
                        if ( $2->n_elems != $1 )
                            htkerror("HTKPARSE:option - STREAMINFO value does not match ivec size\n") ;

                        /* if vec_size is defined, check that sum of stream widths == vec_size */
                        if ( htk_def.global_opts.vec_size > 0 )
                        {
                            for ( i=0,sum=0 ; i<$2->n_elems ; i++ )
                                sum += $2->elems[i] ;
                            if ( sum != htk_def.global_opts.vec_size )
                                htkerror("HTKPARSE:option - sum of stream widths does not equal vec_size\n") ;
                        }
                        
                        /* if we already have a n_streams value - make sure this one is the same */
                        if ( htk_def.global_opts.n_streams > 0 )
                        {
                            if ( htk_def.global_opts.n_streams != $1 )
                                htkerror("HTKPARSE:option - n_streams mismatch\n") ;
                            free( $2->elems ) ;
                        }
                        else
                        {
                            htk_def.global_opts.n_streams = $1 ;
                            htk_def.global_opts.stream_widths = $2->elems ;
                        }
                        free( $2 ) ;
                    }
            |       VECSIZE
                    {
                        int i , sum ;
                        
                        /* if stream_widths are defined, check that sum of stream widths == vec_size */
                        if ( htk_def.global_opts.n_streams > 0 )
                        {
                            for ( i=0,sum=0 ; i<htk_def.global_opts.n_streams ; i++ )
                                sum += htk_def.global_opts.stream_widths[i] ;
                            if ( sum != $1 )
                                htkerror("HTKPARSE:option - sum of stream widths does not equal NEW vec_size\n") ;
                        }

                        /* if we already have a vec_size value - make sure this one is the same */
                        if ( htk_def.global_opts.vec_size > 0 )
                        {
                            if ( htk_def.global_opts.vec_size != $1 )
                                htkerror("HTKPARSE:option - vec_size mismatch\n") ;
                        }
                        else
                            htk_def.global_opts.vec_size = $1 ;
                    }
            |       covkind
                    {
                        if ( htk_def.global_opts.cov_kind != CK_INVALID )
                        {
                            if ( htk_def.global_opts.cov_kind != $1 )
                                htkerror("HTKPARSE:option - cov_kind mismatch\n") ;
                        }
                        else
                            htk_def.global_opts.cov_kind = $1 ;
                    }   
            |       durkind
                    {
                        if ( htk_def.global_opts.dur_kind != DK_INVALID )
                        {
                            if ( htk_def.global_opts.dur_kind != $1 )
                                htkerror("HTKPARSE:option - dur_kind mismatch\n") ;
                        }
                        else
                            htk_def.global_opts.dur_kind = $1 ;
                    }
            |       PARMKIND
                    {
                        if ( htk_def.global_opts.parm_kind_str != NULL )
                        {
                            if ( strcmp( htk_def.global_opts.parm_kind_str , $1 ) != 0 )
                                htkerror("HTKPARSE:option - parm_kind_str already initialised\n") ;
                        }
                        else
                            htk_def.global_opts.parm_kind_str = $1 ;
                    }
            ;

covkind     :       DIAGC    { $$ = CK_DIAGC }
            |       INVDIAGC { $$ = CK_INVDIAGC }
            |       FULLC    { $$ = CK_FULLC }
            |       LLTC     { $$ = CK_LLTC }
            |       XFORMC   { $$ = CK_XFORMC }
            ;

durkind     :       NULLD    { $$ = DK_NULLD }
            |       POISSOND { $$ = DK_POISSOND }
            |       GAMMAD   { $$ = DK_GAMMAD }
            |       GEND     { $$ = DK_GEND }
            ;



/******** SHARED MIXTURE GRAMMAR *********/
/*
shmixdef    :       MMACRO meanvec variancevec
                    {
                        HTKMixture *mix = (HTKMixture *)malloc( sizeof(HTKMixture) ) ;
                        
                        mix->sh_name = $1 ;
                        mix->id = 0 ;
                        mix->weight = 1.0 ;
                        mix->n_means = $2->n_elems ;
                        mix->means = $2->elems ;
                        mix->n_vars = $3->n_elems ;
                        mix->vars = $3->elems ;

                        free( $2 ) ;
                        free( $3 ) ;
                        
                        mix->gconst = 0.0 ;
                        $$ = mix ;
                    }
            ;
*/

/******** Shared Transition Matrix Definition Grammar *******/

shtransmatdef  :    TMACRO transp
                    {
                        $2->sh_name = $1 ;
                        $$ = $2 ;
                    }
               ;

/******** Shared State Definition Grammar *******/

shstatedef  :       SMACRO mixtures
                    {
                        HTKHMMState *st = (HTKHMMState *)malloc( sizeof(HTKHMMState) ) ;
                        
                        /* no <NumMixes>, so assume only a single mixture */
                        if ( $2->n_mixes != 1 )
                            htkerror("HTKPARSE:shstatedef - mixtures n_mixes value != 1\n") ;
                       
                        st->sh_name = $1 ;
                        st->id = -1 ;
                        st->n_mixes = 1 ;
                        st->mixes = $2->mixes ;
                        st->pool_ind = $2->pool_ind ;
                        st->weights = $2->weights ;
                        free( $2 ) ;

                        $$ = st ;
                    }
            |       SMACRO NUMMIXES mixtures
                    {
                        /* allocate a new state */
                        HTKHMMState *st = (HTKHMMState *)malloc( sizeof(HTKHMMState) ) ;
                        
                        /* >= 1 mixture defined */
                        //if ( $3->n_mixes != $2 )
                        //    htkerror("HTKPARSE:shstatedef - mixtures n_mixes value != NUMMIXES value\n") ;
                        
                        /* populate the state structure */
                        st->sh_name = $1 ;
                        st->id = -1 ;
                        st->n_mixes = $3->n_mixes  ;
                        st->mixes = $3->mixes ;
                        st->pool_ind = $3->pool_ind ;
                        st->weights = $3->weights ;
                        free( $3 ) ;

                        $$ = st ;
                    }
            ;

/******** HMM Definition Grammar ********/

hmmdef      :       HMACRO BEGINHMM NUMSTATES optglobopts states transmatdef ENDHMM
                    {
                        HTKHMM *hmm ;

                        /* allocate and initialise a new hmm element */
                        hmm = (HTKHMM *)malloc( sizeof(HTKHMM) ) ;
                        hmm->name = $1 ;
                        hmm->n_states = $3 ;
                        if ( (hmm->n_states-2) != ($5->n_states) )
                            htkerror("HTKPARSE:hmmdef - hmmstatelist n_elems did not match n_states\n") ;
                        hmm->emit_states = $5->states ;
                        free( $5 ) ;
                        hmm->transmat = $6 ;
                        $$ = hmm ;
                    }
            ;

states      :       statedef
                    {
                        HTKHMMStateList *tmp = (HTKHMMStateList *)malloc( sizeof(HTKHMMStateList) ) ;
                        tmp->n_states = 1 ;
                        tmp->states = (HTKHMMState **)malloc( sizeof(HTKHMMState *) ) ;
                        tmp->states[0] = $1 ;
                        $$ = tmp ;
                    }
            |       states statedef
                    {
                        $1->n_states++ ;
                        $1->states = (HTKHMMState **)realloc( $1->states , $1->n_states * sizeof(HTKHMMState *) ) ;
                        $1->states[$1->n_states-1] = $2 ;
                        $$ = $1 ;
                    }
            ;

statedef    :       STATE SMACRO
                    {
                        /* use a shared state */
                        HTKHMMState *st = (HTKHMMState *)malloc( sizeof(HTKHMMState) ) ;
                        int i ;
                        
                        st->sh_name = $2 ;
                        st->id = $1 ;
                        st->n_mixes = 0 ;
                        st->mixes = NULL ;
                        st->pool_ind = -1 ;
                        st->weights = NULL ;
                        
                        /* check that the name of the shared state exists in the list of shared states */
                        for ( i=0 ; i<htk_def.n_sh_states ; i++ )
                        {
                            if ( strcmp( htk_def.sh_states[i]->sh_name , st->sh_name ) == 0 )
                                break ;
                        }
                        if ( i >= htk_def.n_sh_states )
                            htkerror("HTKPARSE:statedef - SMACRO string not found in htk_def\n") ;
                        
                        $$ = st ;
                    }
            |       STATE mixtures
                    {
                        HTKHMMState *st = (HTKHMMState *)malloc( sizeof(HTKHMMState) ) ;
                        
                        /* no <NumMixes>, so assume only a single mixture */
                        if ( $2->n_mixes != 1 )
                            htkerror("HTKPARSE:statedef - mixtures n_mixes value != 1\n") ;
                       
                        st->sh_name = NULL ;
                        st->id = $1 ;
                        st->n_mixes = 1 ;
                        st->mixes = $2->mixes ;
                        st->pool_ind = $2->pool_ind ;
                        st->weights = $2->weights ;
                        free( $2 ) ;

                        $$ = st ;
                    }
            |       STATE NUMMIXES mixtures
                    {
                        /* allocate a new state */
                        HTKHMMState *st = (HTKHMMState *)malloc( sizeof(HTKHMMState) ) ;
                        
                        /* >= 1 mixture defined */
                        
                        // Don't do this check - it seems that sometimes entire mixture 
                        //  components are omitted (probably when their weight is very low), 
                        //  resulting in these 2 values being different.
                        //if ( $3->n_mixes != $2 )
                        //    htkerror("HTKPARSE:statedef - mixtures n_mixes value != NUMMIXES value\n") ;
                        
                        /* populate the state structure */
                        st->sh_name = NULL ;
                        st->id = $1 ;
                        st->n_mixes = $3->n_mixes  ;
                        st->mixes = $3->mixes ;
                        st->pool_ind = $3->pool_ind ;
                        st->weights = $3->weights ;
                        free( $3 ) ;

                        $$ = st ;
                    }
            ;

mixtures    :       TMIX rvector
                    {
                        HTKMixtureList *tmp ;
                        int i ;
                        
                        /* check that the pool name is in our list of mixture pools */
                        for ( i=0 ; i<htk_def.n_mix_pools ; i++ )
                        {
                            if ( strcmp( htk_def.mix_pools[i]->name , $1 ) == 0 )
                                break ;
                        }
                        if ( i >= htk_def.n_mix_pools )
                            htkerror("HTKPARSE:mixtures - TMIX string did not match the name of a mix pool\n") ;
                         
                        /* check that the number of vec elems == num mixes in pool */
                        if ( $2->n_elems != htk_def.mix_pools[i]->n_mixes )
                            htkerror("HTKPARSE:mixtures - tmixweights n_elems did not match n_mixes in mix pool\n") ;
                   
                        /* fill in the mixture list */
                        tmp = (HTKMixtureList *)malloc( sizeof(HTKMixtureList) ) ;
                        tmp->n_mixes = $2->n_elems ;
                        tmp->mixes = NULL ;
                        tmp->pool_ind = i ;
                        tmp->weights = $2->elems ;
                        
                        free( $2 ) ;
                        $$ = tmp ;
                    }
            |       mixturelist
                    {
                        $$ = $1 ;
                    }
            ;
            
mixturelist :       mixturedef
                    {
                        HTKMixtureList *tmp = (HTKMixtureList *)malloc( sizeof(HTKMixtureList) ) ;
                        tmp->n_mixes = 1 ;
                        tmp->pool_ind = -1 ;
                        tmp->weights = NULL ;
                        tmp->mixes = (HTKMixture **)malloc( sizeof(HTKMixture *) ) ;
                        tmp->mixes[0] = $1 ;
                        $$ = tmp ;
                    }
            |       mixtures mixturedef
                    {
                        $1->n_mixes++ ;
                        $1->mixes = (HTKMixture **)realloc( $1->mixes , $1->n_mixes*sizeof(HTKMixture *) ) ;
                        $1->mixes[$1->n_mixes-1] = $2 ;
                        $$ = $1 ;
                    }
            ;

mixturedef  :       MIXTURE REAL mixpdf
                    {
                        $3->id = $1 ;
                        $3->weight = $2 ;
                        $$ = $3 ;
                    }
            |       mixpdf
                    {
                        $1->id = 1 ;
                        $1->weight = 1.0 ;
                        $$ = $1 ;
                    }
            ;
            
mixpdf      :       meanvec variancevec gconst
                    {
                        HTKMixture *mix = (HTKMixture *)malloc( sizeof(HTKMixture) ) ;
                        
                        mix->n_means = $1->n_elems ;
                        mix->means = $1->elems ;
                        mix->n_vars = $2->n_elems ;
                        mix->vars = $2->elems ;

                        free( $1 ) ;
                        free( $2 ) ;
                        
                        mix->gconst = $3 ;
                        $$ = mix ;
                    }
            ;

meanvec     :       MEAN
                    {
                        if ( $1 != htk_def.global_opts.vec_size )
                            htkerror("HTKPARSE:meanvec - MEAN value did not match global vec size\n") ;
                    }
                    rvector
                    {
                        if ( $3->n_elems != $1 )
                            htkerror("HTKPARSE:meanvec - n_elems did not match MEAN value\n") ;
                        $$ = $3 ;
                    }
            ;

variancevec :       VARIANCE
                    {
                        if ( $1 != htk_def.global_opts.vec_size )
                            htkerror("HTKPARSE:variancevec - VARIANCE value did not match global vec size\n") ;
                    }
                    rvector
                    {
                        if ( $3->n_elems != $1 )
                            htkerror("HTKPARSE:variancevec - n_elems did not match VARIANCE value\n") ;
                        $$ = $3 ;
                    }
            ;

gconst      :       /* empty */
                    {
                        $$ = 0.0 ;
                    }
            |       GCONST
                    {
                        $$ = $1 ;
                    }
            ;

transmatdef :       TMACRO
                    {
                        /* use a shared transition matrix */
                        HTKTransMat *tm = (HTKTransMat *)malloc( sizeof(HTKTransMat) ) ;
                        int i ;
                        
                        tm->sh_name = $1 ;
                        tm->n_states = 0 ;
                        tm->transp = NULL ;
                        
                        /* check that the name of the shared TM exists in the list of shared TM's */
                        for ( i=0 ; i<htk_def.n_sh_transmats ; i++ )
                        {
                            if ( strcmp( htk_def.sh_transmats[i]->sh_name , tm->sh_name ) == 0 )
                                break ;
                        }
                        if ( i >= htk_def.n_sh_transmats )
                            htkerror("HTKPARSE:transmatdef - SMACRO string not found in htk_def\n") ;
                        
                        $$ = tm ;
                    }
            |       transp
                    {
                        $$ = $1 ;
                    }
            ;

transp      :       TRANSP rvector
                    {
                        int i , j , k ;
                        HTKTransMat *tm = (HTKTransMat *)malloc( sizeof(HTKTransMat) ) ;
                        
                        if ( $1 != ($2->n_elems / $1) )
                            htkerror("HTKPARSE:transp - vec n_elems did not match TRANSP value\n") ;

                        tm->sh_name = NULL ;
                        tm->n_states = $1 ;
                        tm->transp = (real **)malloc( tm->n_states * sizeof(real *) ) ;
                        for ( i=0,k=0 ; i<tm->n_states ; i++ )
                        {
                            tm->transp[i] = (real *)malloc( tm->n_states * sizeof(real) ) ;
                            for ( j=0 ; j<tm->n_states ; j++ )
                                tm->transp[i][j] = $2->elems[k++] ;
                        }
                        free( $2->elems ) ;
                        free( $2 ) ;

                        $$ = tm ;
                    }
            ;
                        
rvector     :       INTEGER
                    {
                        RealVector *tmp = (RealVector *)malloc( sizeof(RealVector) ) ;
                        tmp->n_elems = 1 ;
                        tmp->elems = (real *)malloc( sizeof(real) ) ;
                        tmp->elems[0] = (real)$1 ;
                        $$ = tmp ;
                    }
            |       REAL
                    {
                        RealVector *tmp = (RealVector *)malloc( sizeof(RealVector) ) ;
                        tmp->n_elems = 1 ;
                        tmp->elems = (real *)malloc( sizeof(real) ) ;
                        tmp->elems[0] = $1 ;
                        $$ = tmp ;
                    }                        
            |       rvector INTEGER
                    {
                        $1->n_elems++ ;
                        $1->elems = (real *)realloc( $1->elems , $1->n_elems*sizeof(real) ) ;
                        $1->elems[$1->n_elems-1] = (real)$2 ;
                        $$ = $1 ;
                    }
            |       rvector REAL
                    {
                        $1->n_elems++ ;
                        $1->elems = (real *)realloc( $1->elems , $1->n_elems*sizeof(real) ) ;
                        $1->elems[$1->n_elems-1] = $2 ;
                        $$ = $1 ;
                    }
            ;
            
ivector     :       INTEGER
                    {
                        IntVector *tmp = (IntVector *)malloc( sizeof(IntVector) ) ;
                        tmp->n_elems = 1 ;
                        tmp->elems = (int *)malloc( sizeof(int) ) ;
                        tmp->elems[0] = $1 ;
                        $$ = tmp ;
                    }
            |       ivector INTEGER
                    {
                        $1->n_elems++ ;
                        $1->elems = (int *)realloc( $1->elems , $1->n_elems*sizeof(int) ) ;
                        $1->elems[$1->n_elems-1] = $2 ;
                        $$ = $1 ;
                    }
            ;

%%


void htkerror( const char *str )
{
    fprintf( stderr , "%s\n" , str ) ;
    exit(1) ;
}


void initHTKDef()
{
   htk_def.global_opts.hmm_set_id = NULL ;
   htk_def.global_opts.n_streams = 0 ;
   htk_def.global_opts.stream_widths = NULL ;
   htk_def.global_opts.vec_size = 0 ;
   htk_def.global_opts.cov_kind = CK_INVALID ;
   htk_def.global_opts.dur_kind = DK_INVALID ;
   htk_def.global_opts.parm_kind_str = NULL ;

   htk_def.n_hmms = 0 ;
   htk_def.hmms = NULL ;

   htk_def.n_sh_transmats = 0 ;
   htk_def.sh_transmats = NULL ;

   htk_def.n_sh_states = 0 ;
   htk_def.sh_states = NULL ;

   htk_def.n_mix_pools = 0 ;
   htk_def.mix_pools = NULL ;
}
    

void cleanHTKDef()
{
    int i , j ;

    /* clean up the global options */
    if ( htk_def.global_opts.hmm_set_id != NULL )
    {
        free( htk_def.global_opts.hmm_set_id ) ;
        htk_def.global_opts.hmm_set_id = NULL ;
    }
    htk_def.global_opts.n_streams = 0 ;
    if ( htk_def.global_opts.stream_widths != NULL )
    {
        free( htk_def.global_opts.stream_widths ) ;
        htk_def.global_opts.stream_widths = NULL ;
    }
    htk_def.global_opts.vec_size = 0 ;
    htk_def.global_opts.cov_kind = CK_INVALID ;
    htk_def.global_opts.dur_kind = DK_INVALID ;
    if ( htk_def.global_opts.parm_kind_str != NULL )
    {
        free( htk_def.global_opts.parm_kind_str ) ;
        htk_def.global_opts.parm_kind_str = NULL ;
    }
    
    /* clean up the shared transition matrices */
    if ( htk_def.sh_transmats != NULL )
    {
        for ( i=0 ; i<htk_def.n_sh_transmats ; i++ )
            cleanTransMat( htk_def.sh_transmats[i] ) ;
        free( htk_def.sh_transmats ) ;
        htk_def.sh_transmats = NULL ;
    }
    htk_def.n_sh_transmats = 0 ;

    /* clean up the shared states */
    if ( htk_def.sh_states != NULL )
    {
        for ( i=0 ; i<htk_def.n_sh_states ; i++ )
            cleanState( htk_def.sh_states[i] ) ;
        free( htk_def.sh_states ) ;
        htk_def.sh_states = NULL ;
    }
    htk_def.n_sh_states = 0 ;
   
    /* clean up the mixture pools */
    if ( htk_def.mix_pools != NULL )
    {
        for ( i=0 ; i<htk_def.n_mix_pools ; i++ )
        {
            if ( htk_def.mix_pools[i]->name != NULL ) 
                free( htk_def.mix_pools[i]->name ) ;
            if ( htk_def.mix_pools[i]->mixes != NULL )
            {
                for ( j=0 ; j<htk_def.mix_pools[i]->n_mixes ; j++ )
                    cleanMixture( htk_def.mix_pools[i]->mixes[j] ) ;
                free( htk_def.mix_pools[i] ) ;
            }
        }
        free( htk_def.mix_pools ) ;
        htk_def.mix_pools = NULL ;
    }
    htk_def.n_mix_pools = 0 ;

    /* clean up the hmms */
    if ( htk_def.hmms != NULL )
    {
        for ( i=0 ; i<htk_def.n_hmms ; i++ )
            cleanHMM( htk_def.hmms[i] ) ;
        free( htk_def.hmms ) ;
        htk_def.hmms = NULL ;
    }
    htk_def.n_hmms = 0 ;
}


void cleanHMM( HTKHMM *hmm )
{
   int i ;

   if ( hmm->name != NULL )
   {
      free( hmm->name ) ;
      hmm->name = NULL ;
   }

   if ( hmm->emit_states != NULL )
   {
      for ( i=0 ; i<(hmm->n_states-2) ; i++ )
         cleanState( hmm->emit_states[i] ) ;
      free( hmm->emit_states ) ;
      hmm->emit_states = NULL ;
   }

   if ( hmm->transmat != NULL )
   {
      cleanTransMat( hmm->transmat ) ;
      hmm->transmat = NULL ;
   }

   free( hmm ) ;
}
    

void cleanTransMat( HTKTransMat *tm )
{
   int i ;

   if ( tm->sh_name != NULL )
   {
      free( tm->sh_name ) ;
      tm->sh_name = NULL ;
   }

   if ( tm->transp != NULL )
   {
      for ( i=0 ; i<tm->n_states ; i++ )
      {
         free( tm->transp[i] ) ;
      }
      free( tm->transp ) ;
      tm->transp = NULL ;
   }
   
   free( tm ) ;
}


void cleanState( HTKHMMState *st )
{
    int i ;
    
    if ( st->sh_name != NULL )
    {
        free( st->sh_name ) ;
        st->sh_name = NULL ;
    }
        
    if ( st->mixes != NULL )
    {
        for ( i=0 ; i<st->n_mixes ; i++ )
            cleanMixture( st->mixes[i] ) ;
        free( st->mixes ) ;
        st->mixes = NULL ;
    }

    if ( st->weights != NULL )
    {
        free( st->weights ) ;
        st->weights = NULL ;
    }

    free( st ) ;
}


void cleanMixture( HTKMixture *mix )
{
    if ( mix->means != NULL )
    {
        free( mix->means ) ;
        mix->means = NULL ;
    }
    if ( mix->vars != NULL )
    {
        free( mix->vars ) ;
        mix->vars = NULL ;
    }
    free( mix ) ;
}


void outputGlobalOpts()
{
    int i ;

    printf("~o\n") ;
    if ( htk_def.global_opts.hmm_set_id != NULL )
        printf("<HMMSETID> %s\n" , htk_def.global_opts.hmm_set_id ) ;
    if ( htk_def.global_opts.n_streams > 0 )
    {
        printf("<STREAMINFO> %d" , htk_def.global_opts.n_streams ) ;
        for ( i=0 ; i<htk_def.global_opts.n_streams ; i++ )
            printf(" %d" , htk_def.global_opts.stream_widths[i] ) ;
        printf("\n") ;
    }
    if ( htk_def.global_opts.vec_size > 0 )
        printf("<VECSIZE> %d\n" , htk_def.global_opts.vec_size ) ;
    if ( htk_def.global_opts.cov_kind != CK_INVALID )
    {
        switch( htk_def.global_opts.cov_kind )
        {
        case CK_DIAGC: printf("<DIAGC>\n") ; break ;
        case CK_INVDIAGC: printf("<INVDIAGC>\n") ; break ;
        case CK_FULLC: printf("<FULLC>\n") ; break ;
        case CK_LLTC: printf("<LLTC>\n") ; break ;
        case CK_XFORMC: printf("<XFORMC>\n") ; break ;
        default: break ;
        }
    }
    if ( htk_def.global_opts.dur_kind != DK_INVALID )
    {
        switch( htk_def.global_opts.dur_kind )
        {
        case DK_NULLD: printf("<NULLD>\n") ; break ;
        case DK_POISSOND: printf("<POISSOND>\n") ; break ;
        case DK_GAMMAD: printf("<GAMMAD>\n") ; break ;
        case DK_GEND: printf("<GEND>\n") ; break ;
        default: break ;
        }
    }
    if ( htk_def.global_opts.parm_kind_str != NULL )
        printf("<%s>\n" , htk_def.global_opts.parm_kind_str ) ;
}


void outputHMMState( HTKHMMState *state , int is_shared )
{
    int i , j ;

    if ( is_shared != 0 )
    {
        printf("~s \"%s\"\n" , state->sh_name ) ;
        printf("<NUMMIXES> %d\n",state->n_mixes) ;
        if ( state->mixes != NULL )
        {
            for ( i=0 ; i<state->n_mixes ; i++ )
            {
                printf("<MIXTURE> %d %.8f\n",state->mixes[i]->id,state->mixes[i]->weight) ;
                printf("<MEAN> %d\n",state->mixes[i]->n_means) ;
                for ( j=0 ; j<state->mixes[i]->n_means ; j++ )
                    printf("%.8f ",state->mixes[i]->means[j]) ;
                printf("\n") ;
                printf("<VARIANCE> %d\n",state->mixes[i]->n_vars) ;
                for ( j=0 ; j<state->mixes[i]->n_vars ; j++ )
                    printf("%.8f ",state->mixes[i]->vars[j]) ;
                printf("\n") ;
            }
        }
        else
        {
            printf("<TMIX> %s" , htk_def.mix_pools[state->pool_ind]->name ) ;
            for ( i=0 ; i<state->n_mixes ; i++ )
                printf(" %.8f" , state->weights[i] ) ;
            printf("\n") ;
        }
    }
    else
    {
        printf("<STATE> %d\n",state->id) ;
        if ( state->sh_name != NULL )
            printf("  ~s \"%s\"\n" , state->sh_name ) ;
        else
        {
            printf("<NUMMIXES> %d\n",state->n_mixes) ;
            if ( state->mixes != NULL )
            {
                for ( i=0 ; i<state->n_mixes ; i++ )
                {
                    printf("<MIXTURE> %d %.8f\n",state->mixes[i]->id,state->mixes[i]->weight) ;
                    printf("<MEAN> %d\n",state->mixes[i]->n_means) ;
                    for ( j=0 ; j<state->mixes[i]->n_means ; j++ )
                        printf("%.8f ",state->mixes[i]->means[j]) ;
                    printf("\n") ;
                    printf("<VARIANCE> %d\n",state->mixes[i]->n_vars) ;
                    for ( j=0 ; j<state->mixes[i]->n_vars ; j++ )
                        printf("%.8f ",state->mixes[i]->vars[j]) ;
                    printf("\n") ;
                }
            }
            else
            {
                printf("<TMIX> %s" , htk_def.mix_pools[state->pool_ind]->name ) ;
                for ( i=0 ; i<state->n_mixes ; i++ )
                    printf(" %.8f" , state->weights[i] ) ;
                printf("\n") ;
            }
        }
    }
}

void outputTransMat( HTKTransMat *tm , int is_shared )
{
   int i , j ;

   if ( is_shared != 0 )
   {
      printf("~t \"%s\"\n" , tm->sh_name ) ;
      printf("<TRANSP> %d\n" , tm->n_states ) ;
      for ( i=0 ; i<tm->n_states ; i++ )
      {
         for ( j=0 ; j<tm->n_states ; j++ )
         {
            printf(" %.8f" , tm->transp[i][j] ) ;
         }
         printf("\n") ;
      }
   }
   else
   {
      if ( tm->sh_name != NULL )
      {
         printf("~t \"%s\"\n" , tm->sh_name ) ;
      }
      else
      {
         printf("<TRANSP> %d\n" , tm->n_states ) ;
         for ( i=0 ; i<tm->n_states ; i++ )
         {
            for ( j=0 ; j<tm->n_states ; j++ )
            {
               printf(" %.8f" , tm->transp[i][j] ) ;
            }
            printf("\n") ;
         }
      }
   }
}


void outputHMM( HTKHMM *hmm )
{
    int i ;
    
    if ( hmm == NULL )
        return ;

    printf("~h \"%s\"\n" , hmm->name ) ;
    printf("<BEGINHMM>\n") ;
    printf("<NUMSTATES> %d\n" , hmm->n_states ) ;

    for ( i=0 ; i<(hmm->n_states-2) ; i++ )
        outputHMMState( hmm->emit_states[i] , 0 ) ;
   
    outputTransMat( hmm->transmat , 0 ) ;

    printf("<ENDHMM>\n") ;
}
            

void outputSharedStates()
{
    int i ;

    for ( i=0 ; i<htk_def.n_sh_states ; i++ )
        outputHMMState( htk_def.sh_states[i] , 1 ) ;
}


void outputSharedTransMats()
{
    int i ;

    for ( i=0 ; i<htk_def.n_sh_transmats ; i++ )
        outputTransMat( htk_def.sh_transmats[i] , 1 ) ;
}


void outputMixturePools()
{
    int i , j , k ;
    HTKMixture *mix ;

    for ( i=0 ; i<htk_def.n_mix_pools ; i++ )
    {
        for ( j=0 ; j<htk_def.mix_pools[i]->n_mixes ; j++ )
        {
            mix = htk_def.mix_pools[i]->mixes[j] ;
            printf("~m \"%s%d\"\n" , htk_def.mix_pools[i]->name , mix->id ) ;
            printf("<MEAN> %d " , mix->n_means ) ;
            for ( k=0 ; k<mix->n_means ; k++ )
                printf("%.8f " , mix->means[k] ) ;
            printf("\n") ;
            printf("<VARIANCE> %d " , mix->n_vars ) ;
            for ( k=0 ; k<mix->n_vars ; k++ )
                printf("%.8f " , mix->vars[k] ) ;
            printf("\n") ;
        }
    }
}