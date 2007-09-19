/*
 * Copyright 2004 by IDIAP Research Institute
 *                   http://www.idiap.ch
 *
 * See the file COPYING for the licence associated with this software.
 */

#ifndef MODELS_INC
#define MODELS_INC

#include "general.h"
#include "htkparse.h"
#include "DecodingHMM.h"

/*
	Author:	Darren Moore (moore@idiap.ch)
	Date:		15 Nov 2004
	$Id: Models.h,v 1.9 2005/08/26 01:16:34 moore Exp $
*/

namespace Juicer {

struct MeanVec
{
   char  *name ;
   real  *means ;
};

struct VarVec
{
   char  *name ;
   real  *vars ;
   real  *minusHalfOverVars ;
   real  sumLogVarPlusNObsLog2Pi ;
};

struct TransMatrix
{
   char  *name ;
   int   nStates ;
   int   *nSucs ;
   int   **sucs ;
   real  **probs ;
   real  **logProbs ;
};

struct Mixture
{
   char  *name ;
   int   nComps ;
   int   *meanVecInds ;
   int   *varVecInds ;
   real  *currCompOutputs ;
   bool  currCompOutputsValid ;
};

struct GMM
{
   char  *name ;
   int   mixtureInd ;
   real  *compWeights ;
   real  *logCompWeights ;
};

/**
 * HMM representation
 */
struct HMM
{
   char  *name ;
   int   nStates ;
   int   *gmmInds ;
   int   transMatrixInd ;   
};


class DecodingHMM ;

/**
 * HTK models
 */
class Models
{
public:
   Models() ;
   Models( const char *phonesListFName , const char *priorsFName , int statesPerModel ) ;
   Models( const char *htkModelsFName , bool removeInitialToFinalTransitions_=false ) ;
   virtual ~Models() ;

   void initFromHTKParseResult() ;
   void readBinary( const char *fName ) ;
   void output( const char *fName , bool outputBinary ) ;
   void outputStats( FILE *fd=stdout ) ;
   void newFrame( int frame , const real *input ) ;
   real calcOutput( int hmmInd , int stateInd ) ;
   real calcOutput( int gmmInd ) ;

   int getNumHMMs() { return nHMMs ; } ;
   int getCurrFrame() { return currFrame ; } ;
   DecodingHMM *getDecHMM( int hmmInd ) { return decHMMs[hmmInd] ; } ;
   HMM *getHMM( int hmmInd ) { return hMMs + hmmInd ; } ;
   int getInputVecSize() { return vecSize ; } ;

private:
   int            currFrame ;
   const real     *currInput ;
   int            vecSize ;

   int            nMeanVecs ;
   int            nMeanVecsAlloc ;
   MeanVec        *meanVecs ;

   int            nVarVecs ;
   int            nVarVecsAlloc ;
   VarVec         *varVecs ;

   bool           removeInitialToFinalTransitions ;
   int            nTransMats ;
   int            nTransMatsAlloc ;
   TransMatrix    *transMats ;

   int            nMixtures ;
   int            nMixturesAlloc ;
   Mixture        *mixtures ;

   int            nGMMs ;
   int            nGMMsAlloc ;
   GMM            *gMMs ;
   real           *currGMMOutputs ;

   int            nHMMs ;
   int            nHMMsAlloc ;
   HMM            *hMMs ;
   DecodingHMM    **decHMMs ;

   FILE           *inFD ;
   FILE           *outFD ;
   bool           fromBinFile ;

   bool           hybridMode ;
   real           *logPriors ;

   int addHMM( HTKHMM *hmm ) ;
   int addGMM( HTKHMMState *st ) ;
   int getGMM( const char *name ) ;
   int addMixture( HTKMixturePool *mix ) ;
   int addMixture( int nComps , HTKMixture **comps ) ;
   int getMixture( const char *name ) ;
   int addMeanVec( const char *name , real *means ) ;
   int addVarVec( const char *name , real *vars ) ;
   int addTransMatrix( const char *name , int nStates , real **trans ) ;
   int getTransMatrix( const char *name ) ;

   void outputHMM( int ind , bool outputBinary ) ;
   void outputGMM( int ind , bool isRef , bool outputBinary ) ;
   void outputMixture( int mixInd , real *compWeights , bool isRef , bool outputBinary ) ;
   void outputMeanVec( int ind , bool isRef , bool outputBinary ) ;
   void outputVarVec( int ind , bool isRef , bool outputBinary ) ;
   void outputTransMat( int ind , bool isRef , bool outputBinary ) ;

   void readBinaryHMM() ;
   void readBinaryGMM() ;
   void readBinaryMixture() ;
   void readBinaryMeanVec() ;
   void readBinaryVarVec() ;
   void readBinaryTransMat() ;

   inline real calcGMMOutput( int gmmInd ) ;
   inline real calcMixtureOutput( int mixInd , const real *logCompWeights ) ;
};


void testModelsIO( const char *htkModelsFName , const char *phonesListFName , 
                   const char *priorsFName , int statesPerModel ) ;

}


#endif
    
    