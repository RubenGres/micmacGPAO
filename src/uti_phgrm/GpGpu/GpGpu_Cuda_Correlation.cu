#include "GpGpu/GpGpu_ParamCorrelation.cuh"
#include "GpGpu/GpGpu_TextureTools.cuh"
#include "GpGpu/GpGpu_TextureCorrelation.cuh"
#include "GpGpu/SData2Correl.h"


/// \file       GpGpuCudaCorrelation.cu
/// \brief      Kernel
/// \author     GC
/// \version    0.2
/// \date       mars 2013

static __constant__ invParamCorrel  invPc;

extern "C" void CopyParamInvTodevice( pCorGpu param )
{
  checkCudaErrors(cudaMemcpyToSymbol(invPc, &param.invPC, sizeof(invParamCorrel)));
}

template<int TexSel> __global__ void projectionImage( HDParamCorrel HdPc, float* projImages, Rect* pRect)
{
    //extern __shared__ float cacheImg[];

    const uint2 ptHTer = make_uint2(blockIdx) *  blockDim.x + make_uint2(threadIdx);

    if (oSE(ptHTer,HdPc.dimDTer)) return;

    const ushort IdLayer = blockDim.z * blockIdx.z + threadIdx.z;

    const float2 ptProj  = GetProjection<TexSel>(ptHTer,invPc.sampProj, IdLayer);

    const Rect  zoneImage = pRect[IdLayer];

    float* localImages = projImages + IdLayer * size(HdPc.dimDTer);

    localImages[to1D(ptHTer,HdPc.dimDTer)] = (oI(ptProj,0)|| oSE( ptHTer, make_uint2(zoneImage.pt1)) || oI(ptHTer,make_uint2(zoneImage.pt0))) ? 1.f : GetImageValue(ptProj,threadIdx.z) / 2048.f;

}

extern "C" void	 LaunchKernelprojectionImage(pCorGpu &param, CuDeviceData3D<float>  &DeviImagesProj, Rect* pRect)
{

    dim3	threads( BLOCKDIM / 2, BLOCKDIM /2, param.invPC.nbImages); // on divise par deux car on explose le nombre de threads par block
    uint2	thd2D		= make_uint2(threads);
    uint2	block2D		= iDivUp(param.HdPc.dimDTer,thd2D);
    dim3	blocks(block2D.x , block2D.y, param.ZCInter);

    DeviImagesProj.ReallocIfDim(param.HdPc.dimDTer,param.ZCInter*param.invPC.nbImages);

    CuHostData3D<float>  hostImagesProj;

    hostImagesProj.ReallocIfDim(param.HdPc.dimDTer,param.ZCInter*param.invPC.nbImages);


    projectionImage<0><<<blocks, threads>>>(param.HdPc,DeviImagesProj.pData(),pRect);

    getLastCudaError("Projection Image");

    DeviImagesProj.CopyDevicetoHost(hostImagesProj);

    //    hostImagesProj.OutputValues();

    for (int z = 0; z < param.ZCInter; ++z)
    {
        for (int i = 0; i < param.invPC.nbImages; ++i)
        {
            std::string nameFile = std::string(GpGpuTools::conca("IMAGES_0",(i+1) * 10 + z)) + std::string(".pgm");
            GpGpuTools::Array1DtoImageFile(hostImagesProj.pData() + (i  + z *  param.invPC.nbImages)* size(hostImagesProj.GetDimension()),nameFile.c_str(),hostImagesProj.GetDimension());
        }
    }

    hostImagesProj.Dealloc();
    DeviImagesProj.Dealloc();

}

/// \fn template<int TexSel> __global__ void correlationKernel( uint *dev_NbImgOk, float* cachVig, uint2 nbActThrd)
/// \brief Kernel fonction GpGpu Cuda
/// Calcul les vignettes de correlation pour toutes les images
///
template<int TexSel> __global__ void correlationKernel( uint *dev_NbImgOk, ushort2 *ClassEqui,float* cachVig, Rect* pRect, uint2 nbActThrd,HDParamCorrel HdPc)
{

  extern __shared__ float cacheImg[];

  // Coordonn�es du terrain global avec bordure // __umul24!!!! A voir

  const uint2 ptHTer = make_uint2(blockIdx) * nbActThrd + make_uint2(threadIdx);

  // Si le processus est hors du terrain, nous sortons du kernel

  if (oSE(ptHTer,HdPc.dimDTer)  ) return;

  const float2 ptProj   = GetProjection<TexSel>(ptHTer,invPc.sampProj,blockIdx.z);
// DEBUT AJOUT 2014
  const Rect  zoneImage = pRect[blockIdx.z];

  uint pitZ,modZ,piCa;

  if (oI(ptProj,0) || ptProj.x >= (float)zoneImage.pt1.x || ptProj.y >= (float)zoneImage.pt1.y /*oSE( ptHTer, make_uint2(zoneImage.pt1)) || oI(ptHTer,make_uint2(zoneImage.pt0))*/) // retirer le 9 decembre 2013 � verifier
  {
      cacheImg[threadIdx.y*BLOCKDIM + threadIdx.x] = -1.f;
      return;
  }// FIN AJOUT 2014
  else
  {
      pitZ  = blockIdx.z / invPc.nbImages;

      piCa  = pitZ * invPc.nbImages;

      modZ  = blockIdx.z - piCa;

      cacheImg[threadIdx.y*BLOCKDIM + threadIdx.x] = GetImageValue(ptProj,modZ);

  }

  __syncthreads();

  const int2 ptTer = make_int2(ptHTer) - make_int2(invPc.rayVig);

  // Nous traitons uniquement les points du terrain du bloque ou Si le processus est hors du terrain global, nous sortons du kernel

  // Simplifier!!!
  // Sortir si threard inactif et si en dehors du terrain
  if (oSE(threadIdx, nbActThrd + invPc.rayVig) || oI(threadIdx , invPc.rayVig) || oSE( ptTer, HdPc.dimTer) || oI(ptTer,0))
    return;

  // DEBUT AJOUT 2014 // TODO A SIMPLIFIER --> peut etre simplifier avec la zone terrain!
  // Sortir si endehors de
 // if ( oSE( ptHTer + invPc.rayVig.x , make_uint2(zoneImage.pt1)) || oI(ptTer,zoneImage.pt0))
  //if ( oSE( ptHTer + invPc.rayVig.x , make_uint2(zoneImage.pt1)) || oI(ptHTer - invPc.rayVig.x ,make_uint2(zoneImage.pt0)))
      //return;

  if ( oI( ptProj - invPc.rayVig.x-1, 0) | ptProj.x + invPc.rayVig.x+1>= (float)zoneImage.pt1.x || ptProj.y + invPc.rayVig.x+1>= (float)zoneImage.pt1.y)
      return;
  // FIN AJOUT 2014

  // INCORRECT !!! TODO
  // COM 6 mars 2014
  if(tex2D(TexS_MaskGlobal, ptTer.x + HdPc.rTer.pt0.x , ptTer.y + HdPc.rTer.pt0.y) == 0) return;

  const short2 c0	= make_short2(threadIdx) - invPc.rayVig;
  const short2 c1	= make_short2(threadIdx) + invPc.rayVig;

  // Intialisation des valeurs de calcul
  float aSV = 0.0f, aSVV = 0.0f;
  short2 pt;

  #pragma unroll // ATTENTION PRAGMA FAIT AUGMENTER LA quantit� MEMOIRE des registres!!!
  for (pt.y = c0.y ; pt.y <= c1.y; pt.y++)
  {
        //const int pic = pt.y*BLOCKDIM;
        float* cImg    = cacheImg +  pt.y*BLOCKDIM;
      #pragma unroll
      for (pt.x = c0.x ; pt.x <= c1.x; pt.x++)
      {
          const float val = cImg[pt.x];	// Valeur de l'image

          //if (val ==  invPc.floatDefault) return;
          aSV  += val;          // Somme des valeurs de l'image cte
          aSVV += (val*val);	// Somme des carr�s des vals image cte
      }
  }

  aSV   = fdividef(aSV,(float)invPc.sizeVig );

  aSVV  = fdividef(aSVV,(float)invPc.sizeVig );

  aSVV -=	(aSV * aSV);

  if ( aSVV <= invPc.mAhEpsilon) return;

  aSVV =	rsqrtf(aSVV); // racine carre inverse

  const uint pitchCachY = ptTer.y * invPc.dimVig.y ;

  const ushort iCla = ClassEqui[modZ].x;

  const ushort pCla = ClassEqui[iCla].y; 

  const int  idN    = (pitZ * invPc.nbClass + iCla ) * HdPc.sizeTer + to1D(ptTer,HdPc.dimTer);

  const uint iCa    = atomicAdd( &dev_NbImgOk[idN], 1U) + piCa + pCla;

  float* cache      = cachVig + (iCa * HdPc.sizeCach) + ptTer.x * invPc.dimVig.x - c0.x + (pitchCachY - c0.y)* HdPc.dimCach.x;

#pragma unroll
  for ( pt.y = c0.y ; pt.y <= c1.y; pt.y++)
    {
      float* cImg = cacheImg + pt.y * BLOCKDIM;
      float* cVig = cache    + pt.y * HdPc.dimCach.x ;
#pragma unroll
      for ( pt.x = c0.x ; pt.x <= c1.x; pt.x++)

          cVig[ pt.x ] = (cImg[pt.x] -aSV)*aSVV;

    }
}

/// \brief Fonction qui lance les kernels de correlation
extern "C" void	 LaunchKernelCorrelation(const int s,cudaStream_t stream,pCorGpu &param,SData2Correl &data2cor)
{

    dim3	threads( BLOCKDIM, BLOCKDIM, 1);
    uint2	thd2D		= make_uint2(threads);
    uint2	nbActThrd	= thd2D - 2 * param.invPC.rayVig;
    uint2	block2D		= iDivUp(param.HdPc.dimDTer,nbActThrd);
    dim3	blocks(block2D.x , block2D.y, param.invPC.nbImages * param.ZCInter);

//    CuDeviceData3D<float>       DeviImagesProj;
//    LaunchKernelprojectionImage(param,DeviImagesProj,data2cor.DeviRect());
//    DeviImagesProj.Dealloc();

    switch (s)
    {
    case 0:
        correlationKernel<0><<<blocks, threads, BLOCKDIM * BLOCKDIM * sizeof(float), stream>>>( data2cor.DeviVolumeNOK(0),data2cor.DeviClassEqui(), data2cor.DeviVolumeCache(0),data2cor.DeviRect(), nbActThrd,param.HdPc);
        getLastCudaError("Basic Correlation kernel failed stream 0");
        break;
    case 1:
        correlationKernel<1><<<blocks, threads, BLOCKDIM * BLOCKDIM* sizeof(float), stream>>>( data2cor.DeviVolumeNOK(1),data2cor.DeviClassEqui(), data2cor.DeviVolumeCache(1),data2cor.DeviRect(), nbActThrd,param.HdPc);
        getLastCudaError("Basic Correlation kernel failed stream 1");
        break;
    }
}


/// \brief Kernel Calcul "rapide"  de la multi-correlation en utilisant la formule de Huygens n utilisant pas des fonctions atomiques

template<ushort SIZE3VIGN > __global__ void multiCorrelationKernel(ushort2* classEqui,float *dTCost, float* cacheVign, uint* dev_NbImgOk, /*uint2 nbActThr,*/HDParamCorrel HdPc)
{

  __shared__ float aSV [ SIZE3VIGN   ][ SIZE3VIGN ];          // Somme des valeurs
  __shared__ float aSVV[ SIZE3VIGN   ][ SIZE3VIGN ];         // Somme des carr�s des valeurs
  __shared__ float resu[ SIZE3VIGN/2 ][ SIZE3VIGN/2 ];		// resultat

  __shared__ float cResu[ SIZE3VIGN/2][ SIZE3VIGN/2 ];		// resultat
  __shared__ uint nbIm[ SIZE3VIGN/2][ SIZE3VIGN/2 ];		// nombre d'images correcte

  // coordonn�es des threads // TODO uint2 to ushort2
  const uint2 t  = make_uint2(threadIdx);
  //const uint2 mt = make_uint2(t.x/2,t.y/2);

  // TODO : 2014 LE NOMBRE DE TREAD ACTIF peut etre nettement ameliorer par un template
  //if ( oSE( t, nbActThr))	return; // si le thread est inactif, il sort

  // Coordonn�es 2D du cache vignette
  const uint2 ptCach = make_uint2(blockIdx) * SIZE3VIGN + t;

  // Si le thread est en dehors du cache // TODO 2014 � verifier ----
  if ( oSE(ptCach, HdPc.dimCach))	return;

  const uint2	ptTer	= ptCach / invPc.dimVig; // Coordonn�es 2D du terrain

  // if(!tex2D(TexS_MaskGlobal, ptTer.x + HdPc.rTer.pt0.x , ptTer.y + HdPc.rTer.pt0.y)) return;// COM 6 mars 2014// TODO 2014 � verifier notamment quand il n'y a pas de cache!!!

  const uint    ter     = to1D(ptTer, HdPc.dimTer);            // Coordonn�es 1D du terrain

  const uint	iTer	= blockIdx.z * HdPc.sizeTer + ter;     // Coordonn�es 1D du terrain avec prise en compte des differents Z

  const uint2   thTer	= t / invPc.dimVig;                    // Coordonn�es 2D du terrain dans le repere des threads

  const bool mainThread = aEq(t - thTer*invPc.dimVig,0);

  //if (!aEq(t - thTer*invPc.dimVig,0))
  //{
      resu[thTer.y][thTer.x]    = 0.0f;
      nbIm[thTer.y][thTer.x]    = 0;
  //}

  __syncthreads();

  for (ushort iCla = 0; iCla < invPc.nbClass; ++iCla)
  {

      const uint icTer    = (blockIdx.z* invPc.nbClass + iCla ) * HdPc.sizeTer + ter;

      const ushort nImgOK = (ushort)dev_NbImgOk[icTer];

      aSV [t.y][t.x]    = 0.0f;
      aSVV[t.y][t.x]    = 0.0f;
      cResu[thTer.y][thTer.x]	= 0.0f;

      //__syncthreads();

      if ( nImgOK > 1)
      {

          const uint pitCla         = ((uint)classEqui[iCla].y) * HdPc.sizeCach;

          const uint pitLayerCache  = blockIdx.z  * HdPc.sizeCachAll + pitCla + to1D( ptCach, HdPc.dimCach );	// Taille du cache vignette pour une image

          float* caVi = cacheVign + pitLayerCache;

 #pragma unroll
          for(uint i =  0 ;i< nImgOK * HdPc.sizeCach ;i+=HdPc.sizeCach)
          {
              const float val  = caVi[i];
              aSV[t.y][t.x]   += val;
              aSVV[t.y][t.x]  += val * val;
          }

          //__syncthreads();

          //atomicAdd(&(resu[thTer.y][thTer.x]),(aSVV[t.y][t.x] - fdividef(aSV[t.y][t.x] * aSV[t.y][t.x],(float)nImgOK)) * (nImgOK - 1));

          atomicAdd(&(cResu[thTer.y][thTer.x]),(aSVV[t.y][t.x] - fdividef(aSV[t.y][t.x] * aSV[t.y][t.x],(float)nImgOK)));

          __syncthreads();

          if (mainThread)
          {
              const uint n = nImgOK - 1;

              float ccost =  fdividef( cResu[thTer.y][thTer.x], ((float)n)* (invPc.sizeVig));

              ccost = 1.0f - max (-1.0, min(1.0f,1.0f - ccost));

              resu[thTer.y][thTer.x] += ccost * nImgOK;
              nbIm[thTer.y][thTer.x] += nImgOK;
          }
      }
  }

  __syncthreads();
  if( (nbIm[thTer.y][thTer.x] == 0) || (!mainThread) ) return;

  //__syncthreads();

  // Normalisation pour le ramener a un equivalent de 1-Correl
  //const float cost =  fdividef( resu[thTer.y][thTer.x], ((float)nImgOK -1.0f) * (invPc.sizeVig));

  //const float cost =  fdividef( resu[thTer.y][thTer.x], ((float)nbIm[thTer.y][thTer.x])* (invPc.sizeVig));

  //const float cost =  fdividef( resu[thTer.y][thTer.x], ((float)nbIm[thTer.y][thTer.x] -1)* (invPc.sizeVig));

  //dTCost[iTer] = 1.0f - max (-1.0, min(1.0f,1.0f - cost));

  dTCost[iTer] = fdividef(resu[thTer.y][thTer.x],(float)nbIm[thTer.y][thTer.x]);

}

template<ushort SIZE3VIGN > void LaunchKernelMultiCor(cudaStream_t stream, pCorGpu &param, SData2Correl &dataCorrel)
{
    //-------------	calcul de dimension du kernel de multi-correlation NON ATOMIC ------------
    //uint2	nbActThr	= SIZE3VIGN - make_uint2( SIZE3VIGN % param.invPC.dimVig.x, SIZE3VIGN % param.invPC.dimVig.y);
    dim3	threads(SIZE3VIGN, SIZE3VIGN, 1);
    uint2	block2D	= iDivUp(param.HdPc.dimCach,SIZE3VIGN);
    dim3	blocks(block2D.x,block2D.y,param.ZCInter);

    multiCorrelationKernel<SIZE3VIGN><<<blocks, threads, 0, stream>>>(dataCorrel.DeviClassEqui(),dataCorrel.DeviVolumeCost(0), dataCorrel.DeviVolumeCache(0), dataCorrel.DeviVolumeNOK(0),param.HdPc);
    getLastCudaError("Multi-Correlation NON ATOMIC kernel failed");
}

/// \brief Fonction qui lance les kernels de multi-Correlation n'utilisant pas des fonctions atomiques
extern "C" void LaunchKernelMultiCorrelation(cudaStream_t stream, pCorGpu &param, SData2Correl &dataCorrel)
{
    if(param.invPC.rayVig.x == 1 || param.invPC.rayVig.x == 2 )
        LaunchKernelMultiCor<SBLOCKDIM>(stream, param, dataCorrel);
    else if(param.invPC.rayVig.x == 3 )
        LaunchKernelMultiCor<7*2>(stream, param, dataCorrel);

}

/*
template<int TexSel> __global__ void correlationKernelZ( uint *dev_NbImgOk, float* cachVig, uint2 nbActThrd,float* imagesProj,HDParamCorrel HdPc)
{

    extern __shared__ float cacheImgLayered[];

    float* cacheImg = cacheImgLayered + threadIdx.z * BLOCKDIM * BLOCKDIM;

    // Coordonn�es du terrain global avec bordure // __umul24!!!! A voir

    const uint2 ptHTer = make_uint2(blockIdx) * nbActThrd + make_uint2(threadIdx);

    // Si le processus est hors du terrain, nous sortons du kernel

    if (oSE(ptHTer,HdPc.dimDTer)) return;

    const ushort pitImages = blockIdx.z * invPc.nbImages;

    const float v = cacheImg[threadIdx.y*BLOCKDIM + threadIdx.x] = imagesProj[ ( pitImages + threadIdx.z) * size(HdPc.dimDTer) + to1D(ptHTer,HdPc.dimDTer) ];

    if(v < 0)
        return;

    __syncthreads();

    const int2 ptTer = make_int2(ptHTer) - make_int2(invPc.rayVig);

    // Nous traitons uniquement les points du terrain du bloque ou Si le processus est hors du terrain global, nous sortons du kernel

    // Simplifier!!!
    if (oSE(threadIdx, nbActThrd + invPc.rayVig) || oI(threadIdx , invPc.rayVig) || oSE( ptTer, HdPc.dimTer) || oI(ptTer, 0))
      return;


    // INCORRECT !!!
    if(tex2D(TexS_MaskGlobal, ptTer.x + HdPc.rTer.pt0.x , ptTer.y + HdPc.rTer.pt0.y) == 0) return;

    const short2 c0	= make_short2(threadIdx) - invPc.rayVig;
    const short2 c1	= make_short2(threadIdx) + invPc.rayVig;

    // Intialisation des valeurs de calcul
    float aSV = 0.0f, aSVV = 0.0f;
    short2 pt;

    #pragma unroll // ATTENTION PRAGMA FAIT AUGMENTER LA quantit� MEMOIRE des registres!!!
    for (pt.y = c0.y ; pt.y <= c1.y; pt.y++)
    {
          //const int pic = pt.y*BLOCKDIM;
          float* cImg    = cacheImg +  pt.y*BLOCKDIM;
        #pragma unroll
        for (pt.x = c0.x ; pt.x <= c1.x; pt.x++)
        {
            const float val = cImg[pt.x];	// Valeur de l'image
            //        if (val ==  cH.floatDefault) return;
            aSV  += val;          // Somme des valeurs de l'image cte
            aSVV += (val*val);	// Somme des carr�s des vals image cte
        }
    }

    aSV   = fdividef(aSV,(float)invPc.sizeVig );

    aSVV  = fdividef(aSVV,(float)invPc.sizeVig );

    aSVV -=	(aSV * aSV);

    if ( aSVV <= invPc.mAhEpsilon) return;

    aSVV =	rsqrtf(aSVV); // racine carre inverse

    const uint pitchCachY = ptTer.y * invPc.dimVig.y ;

    const int idN     = blockIdx.z * HdPc.sizeTer + to1D(ptTer,HdPc.dimTer);

    float* cache      = cachVig + (atomicAdd( &dev_NbImgOk[idN], 1U) + pitImages) * HdPc.sizeCach + ptTer.x * invPc.dimVig.x - c0.x + (pitchCachY - c0.y)* HdPc.dimCach.x;

  #pragma unroll
    for ( pt.y = c0.y ; pt.y <= c1.y; pt.y++)
      {
        float* cImg = cacheImg + pt.y * BLOCKDIM;
        float* cVig = cache    + pt.y * HdPc.dimCach.x ;
  #pragma unroll
        for ( pt.x = c0.x ; pt.x <= c1.x; pt.x++)
          cVig[ pt.x ] = (cImg[pt.x] -aSV)*aSVV;
      }
}

/// \brief Fonction qui lance les kernels de correlation
extern "C" void	 LaunchKernelCorrelationZ(const int s,pCorGpu &param,SData2Correl &data2cor)
{

    dim3	threads( BLOCKDIM, BLOCKDIM, param.invPC.nbImages);
    uint2	thd2D		= make_uint2(threads);
    uint2	nbActThrd	= thd2D - 2 * param.invPC.rayVig;
    uint2	block2D		= iDivUp(param.HdPc.dimDTer,nbActThrd);
    dim3	blocks(block2D.x , block2D.y, param.ZCInter);

    CuDeviceData3D<float>       DeviImagesProj;

    //const ushort HBLOCKDIM = BLOCKDIM + param.invPC.rayVig.x;

    LaunchKernelprojectionImage(param,DeviImagesProj,data2cor.DeviRect());

    DeviImagesProj.Dealloc();

    correlationKernelZ<0><<<blocks, threads, param.invPC.nbImages * BLOCKDIM * BLOCKDIM * sizeof(float), 0>>>(
                                                                                           data2cor.DeviVolumeNOK(0),
                                                                                           data2cor.DeviVolumeCache(0),
                                                                                           nbActThrd,
                                                                                           DeviImagesProj.pData(),
                                                                                           param.HdPc);
    getLastCudaError("Basic Correlation kernel failed stream 0");

}
*/
