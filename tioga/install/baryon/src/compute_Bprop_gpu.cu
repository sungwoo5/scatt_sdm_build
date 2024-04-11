#include <complex>
#include <iostream>


// CUDA runtime
#include <cuda.h>
#include <cuda_runtime.h>
#include <cublas_v2.h>

#include <compute_Bprop_gpu.h>

// using namespace std;
// using cd = std::complex<double>;
// using Tensor2 = Eigen::Tensor<cd,2>;
// using Tensor4 = Eigen::Tensor<cd,4>;


Tensor4 multiply_Tensor2xTensor4(const Tensor2 A, const Tensor4 B)
{
  const auto& Adim = A.dimensions();
  const auto& Bdim = B.dimensions();
  // cout<< "Adim=" << Adim[0] << ", "<<Adim[1] << endl;
  // cout<< "Bdim=" << Bdim[0] << ", "<<Bdim[1] << ", "<<Bdim[2] << ", "<<Bdim[3] << endl;


  

  // allocate device memory
  cuDoubleComplex *d_A, *d_B, *d_C;

  // column major: A[alpha,l]=h_A[l*Adim[0] + alpha]
  const cd *h_A=A.data();	

  // column major: B[i,j,k,l]=h_B[l*Bdim[0]*Bdim[1]*Bdim[2] + k*Bdim[0]*Bdim[1] + j*Bdim[0] + i]
  //              =B[ijk,l]  =h_B[l*Bdim[0]*Bdim[1]*Bdim[2] + ijk]
  //     where ijk=k*Bdim[0]*Bdim[1] + j*Bdim[0] + i
  const cd *h_B=B.data();		



  // what we want
  // A[alpha,l] * B[ijk,l] = A[alpha,l] * B^T [l,ijk] = C[alpha,ijk]

  // C     = A    * B^T ;  where B
  // [MxN] = [MxK]*[KxN];        [NxK]
  size_t M,N,K;

  M=Adim[0];
  K=Adim[1];			// should be equal to Bdim[3]
  N=Bdim[0]*Bdim[1]*Bdim[2];

  size_t mem_size_A=M*K*sizeof(cd);
  size_t mem_size_B=N*K*sizeof(cd);
  size_t mem_size_C=M*N*sizeof(cd);
    
  cudaMalloc((void **) &d_A, mem_size_A);
  cudaMalloc((void **) &d_B, mem_size_B);
  cudaMemcpy(d_A, h_A, mem_size_A, cudaMemcpyHostToDevice);
  cudaMemcpy(d_B, h_B, mem_size_B, cudaMemcpyHostToDevice);
  cudaMalloc((void **) &d_C, mem_size_C);

  // CUBLAS version 2.0
  {
    // const float alpha = 1.0f;
    // const float beta  = 0.0f;
    cuDoubleComplex alpha = make_cuDoubleComplex(1.0, 0.);
    cuDoubleComplex beta = make_cuDoubleComplex(0.0, 0.);
    // cd alpha(1.0, 0.0);
    // cd beta(0.0, 0.0);

    // cuDoubleComplex* _alpha = reinterpret_cast<cuDoubleComplex*>(&alpha);
    // cuDoubleComplex* _beta = reinterpret_cast<cuDoubleComplex*>(&beta);

    cublasHandle_t handle;	// reuse as much as we can?

    cublasCreate(&handle);

    cublasZgemm3m(handle, 
    		  CUBLAS_OP_N, CUBLAS_OP_T, 
    		  M, N, K,
    		  &alpha, 
    		  d_A, M,
    		  d_B, N, 
    		  &beta, 
    		  d_C, M);

    cublasDestroy(handle);
  }

  Tensor4 C(Adim[0],Bdim[0],Bdim[1],Bdim[2]);
  cd *h_C=C.data();

  cudaMemcpy(h_C, d_C, mem_size_C, cudaMemcpyDeviceToHost);
  

  cudaFree(d_A);
  cudaFree(d_B);
  cudaFree(d_C);

  return C;
} 

// 1d cuDoubleComplex d_B and d_C for implicit rank4 tensors
// allocate memory and pass the result d_C
void multiply_Tensor2xcuDoubleComp4(cuDoubleComplex **d_C, 
				    const Tensor2 A,
				    cuDoubleComplex **d_B, const std::vector<int> &Bdim,
				    cublasHandle_t *handle)
{
  const auto& Adim = A.dimensions();
  // cout<< "Adim=" << Adim[0] << ", "<<Adim[1] << endl;
  // cout<< "Bdim=" << Bdim[0] << ", "<<Bdim[1] << ", "<<Bdim[2] << ", "<<Bdim[3] << endl;


  

  // allocate device memory
  cuDoubleComplex *d_A;

  // column major: A[alpha,l]=h_A[l*Adim[0] + alpha]
  const cd *h_A=A.data();	

  // column major: B[i,j,k,l]=h_B[l*Bdim[0]*Bdim[1]*Bdim[2] + k*Bdim[0]*Bdim[1] + j*Bdim[0] + i]
  //              =B[ijk,l]  =h_B[l*Bdim[0]*Bdim[1]*Bdim[2] + ijk]
  //     where ijk=k*Bdim[0]*Bdim[1] + j*Bdim[0] + i

  // what we want
  // A[alpha,l] * B[ijk,l] = A[alpha,l] * B^T [l,ijk] = C[alpha,ijk]

  // C     = A    * B^T ;  where B
  // [MxN] = [MxK]*[KxN];        [NxK]
  size_t M,N,K;

  M=Adim[0];
  K=Adim[1];			// should be equal to Bdim[3]
  N=Bdim[0]*Bdim[1]*Bdim[2];

  size_t mem_size_A=M*K*sizeof(cd);
  size_t mem_size_B=N*K*sizeof(cd);
  size_t mem_size_C=M*N*sizeof(cd);
    
  cudaMalloc((void **) &d_A, mem_size_A);
  cudaMemcpy(d_A, h_A, mem_size_A, cudaMemcpyHostToDevice);
  cudaMalloc((void **) d_C, mem_size_C);

  // CUBLAS version 2.0
  {
    cuDoubleComplex alpha = make_cuDoubleComplex(1.0, 0.);
    cuDoubleComplex beta = make_cuDoubleComplex(0.0, 0.);

    cublasZgemm3m(*handle, 
    		  CUBLAS_OP_N, CUBLAS_OP_T, 
    		  M, N, K,
    		  &alpha, 
    		  d_A, M,
    		  *d_B, N, 
    		  &beta, 
    		  *d_C, M);
    
  }

  cudaFree(d_A);
  // cudaFree(*d_B);
} 



Tensor4 compute_Bprop_gpu(vector<Spin4> &spintensor, 
			  const Tensor2 omega, 
			  const Tensor4 tsource,
			  int NSPIN,
			  int NVEC
			  )
{
  cudaError status;
  cublasHandle_t handle;	// reuse as much as we can
  cublasCreate(&handle);

  // output device
  cuDoubleComplex *d_Bprop;
  size_t n_size_Bprop=NSPIN*NVEC*NSPIN*NVEC*NSPIN*NVEC*NSPIN*NVEC;
  size_t mem_size_Bprop=n_size_Bprop*sizeof(cd);
  cudaMalloc((void **) &d_Bprop, mem_size_Bprop);
  cudaMemset(d_Bprop, 0, mem_size_Bprop);

  // input tsource array
  cuDoubleComplex *d_tsource, *d_c3, *d_c2, *d_c1, *d_res;
  cudaMalloc((void **) &d_tsource, NVEC*NVEC*NVEC*NVEC*sizeof(cd));
  const cd *h_tsource=tsource.data();
  status = cudaMemcpy(d_tsource, h_tsource, NVEC*NVEC*NVEC*NVEC*sizeof(cd), cudaMemcpyHostToDevice);
  if(status != cudaSuccess)
    {
      fprintf(stderr, "cudaMemcpyHostToDevice\n");
      exit(0);
    }

  // for input omega array
  Eigen::array<Eigen::IndexPair<int>, 1> indices = { Eigen::IndexPair<int>(1,3) }; 
  Eigen::array<Eigen::Index, 2> extents = {NSPIN*NVEC, NVEC};

  for(vector<Spin4>::const_iterator sp = spintensor.begin(); sp!= spintensor.end(); ++sp)
    {
      // omega with source spin component fixed
      int s0=sp->s[0];	// 1st spin index
      int s1=sp->s[1];	// 2nd spin index
      int s2=sp->s[2];	// 3rd spin index
      int s3=sp->s[3];	// 4th spin index
        

      // d_c3=(3,7)x(4567)
      //     =(3456) [Ns*Nvec,Nvec,Nvec,Nvec]
      Eigen::array<Eigen::Index, 2> offsets_s3 = {0, s3*NVEC};
      Tensor2 omega_s3=omega.slice(offsets_s3, extents); // [Ns*Nvec,Nvec]
      std::vector<int> dim_tsource{NVEC,NVEC,NVEC,NVEC};
      multiply_Tensor2xcuDoubleComp4(&d_c3, omega_s3, &d_tsource, dim_tsource, &handle);
      // note that d_tsource is not freed, will be reused for the next sp
      // the output d_c3 will be used in the next call below

      // d_c2=(2,6)x(3456)
      //     =(2345) [Ns*Nvec,Ns*Nvec,Nvec,Nvec]
      Eigen::array<Eigen::Index, 2> offsets_s2 = {0, s2*NVEC};
      Tensor2 omega_s2=omega.slice(offsets_s2, extents); // [Ns*Nvec,Nvec]
      std::vector<int> dim_c3{NSPIN*NVEC,NVEC,NVEC,NVEC};
      multiply_Tensor2xcuDoubleComp4(&d_c2, omega_s2, &d_c3, dim_c3, &handle);
      // the input d_c3 is temporary and not needed anymore
      cudaFree(d_c3);

      // d_c1=(1,5)x(2345)
      //     =(1234) [Ns*Nvec,Ns*Nvec,Ns*Nvec,Nvec]
      Eigen::array<Eigen::Index, 2> offsets_s1 = {0, s1*NVEC};
      Tensor2 omega_s1=omega.slice(offsets_s1, extents); // [Ns*Nvec,Nvec]
      std::vector<int> dim_c2{NSPIN*NVEC,NSPIN*NVEC,NVEC,NVEC};
      multiply_Tensor2xcuDoubleComp4(&d_c1, omega_s1, &d_c2, dim_c2, &handle);
      cudaFree(d_c2);

      // d_res=(0,4)x(1234)
      //      =(0123) [Ns*Nvec,Ns*Nvec,Ns*Nvec,Ns*Nvec]
      Eigen::array<Eigen::Index, 2> offsets_s0 = {0, s0*NVEC};
      Tensor2 omega_s0=omega.slice(offsets_s0, extents); // [Ns*Nvec,Nvec]
      std::vector<int> dim_c1{NSPIN*NVEC,NSPIN*NVEC,NSPIN*NVEC,NVEC};
      multiply_Tensor2xcuDoubleComp4(&d_res, omega_s0, &d_c1, dim_c1, &handle);
      cudaFree(d_c1);

      // d_Bprop += d_res * conj(sp->val);
      // add with the value of sp, the sparse spin matrix element
      // NOTE THAT source gamma needs complex conjugate!
      cuDoubleComplex alpha = make_cuDoubleComplex(sp->val.real(), -sp->val.imag());
      cublasZaxpy(handle, n_size_Bprop, 
		  &alpha,
		  d_res, 1,
		  d_Bprop, 1);
      cudaFree(d_res);
    }

  // transfer the result d_Bprop to the host
  Tensor4 Bprop(NSPIN*NVEC,NSPIN*NVEC,NSPIN*NVEC,NSPIN*NVEC);
  cd *h_Bprop=Bprop.data();
  cudaMemcpy(h_Bprop, d_Bprop, mem_size_Bprop, cudaMemcpyDeviceToHost);
  cudaFree(d_Bprop);
  
  cudaFree(d_tsource);
 

  cublasDestroy(handle);
  return Bprop;
}

#define MAX_BLOCK 65535 //2^15=32768, 2^16=65536
#define MAX_THREADS 1024

				    
__global__ void cross_Tensor4xspin4(cuDoubleComplex *out,
				    cuDoubleComplex *in, 
				    cuDoubleComplex *alpha, 
				    int N,
				    int s0, int s1, int s2, int s3)
{
  size_t idx=blockIdx.x*blockDim.x + threadIdx.x; 
  size_t idx_cross;
  int l[4], tmp, ls[4];
  int Ns=N*4;
  l[0]=idx%N;			// column major
  tmp=idx/N;
  l[1]=tmp%N;
  tmp=tmp/N;
  l[2]=tmp%N;
  tmp=tmp/N;
  l[3]=tmp%N;

  ls[0]=s0*N+l[0];
  ls[1]=s1*N+l[1];
  ls[2]=s2*N+l[2];
  ls[3]=s3*N+l[3];
  

  // column major index
  idx_cross = ls[0] + ls[1]*Ns + ls[2]*Ns*Ns + ls[3]*Ns*Ns*Ns;
  cuDoubleComplex cutmp=out[idx_cross];
  out[idx_cross] = cuCadd(cutmp, cuCmul(in[idx],*alpha));
}

Tensor4 compute_Bsink_gpu(vector<Spin4> &spintensor, 
			  const Tensor4 tsink,
			  int NSPIN,
			  int NVEC
			  )
{
  cudaError status;

  int threads;
  size_t size = NVEC*NVEC*NVEC*NVEC;
  for(threads = MAX_THREADS; threads >= 1; threads--){
    if( size%threads == 0) break;
  }
  int block = size/threads;

  // output device
  cuDoubleComplex *d_Bsink;
  size_t n_size_Bsink=NSPIN*NVEC*NSPIN*NVEC*NSPIN*NVEC*NSPIN*NVEC;
  size_t mem_size_Bsink=n_size_Bsink*sizeof(cd);
  cudaMalloc((void **) &d_Bsink, mem_size_Bsink);
  cudaMemset(d_Bsink, 0, mem_size_Bsink);

  // input tsink array
  cuDoubleComplex *d_tsink;
  cudaMalloc((void **) &d_tsink, NVEC*NVEC*NVEC*NVEC*sizeof(cd));
  const cd *h_tsink=tsink.data();
  status = cudaMemcpy(d_tsink, h_tsink, NVEC*NVEC*NVEC*NVEC*sizeof(cd), cudaMemcpyHostToDevice);
  if(status != cudaSuccess)
    {
      fprintf(stderr, "cudaMemcpyHostToDevice\n");
      exit(0);
    }

  for(vector<Spin4>::const_iterator sp = spintensor.begin(); sp!= spintensor.end(); ++sp)
    {
      // omega with sink spin component fixed
      int s0=sp->s[0];	// 1st spin index
      int s1=sp->s[1];	// 2nd spin index
      int s2=sp->s[2];	// 3rd spin index
      int s3=sp->s[3];	// 4th spin index
        
      // d_Bsink += d_res * sp->val;
      // add with the value of sp, the sparse spin matrix element
      cuDoubleComplex alpha = make_cuDoubleComplex(sp->val.real(), sp->val.imag());

      cross_Tensor4xspin4<<<block, threads >>>(d_Bsink, d_tsink, &alpha,
					       NVEC, 
					       s0,s1,s2,s3);
      
    }

  // transfer the result d_Bsink to the host
  Tensor4 Bsink(NSPIN*NVEC,NSPIN*NVEC,NSPIN*NVEC,NSPIN*NVEC);
  cd *h_Bsink=Bsink.data();
  status = cudaMemcpy(h_Bsink, d_Bsink, mem_size_Bsink, cudaMemcpyDeviceToHost);
  if(status != cudaSuccess)
    {
      fprintf(stderr, "cudaMemcpyDeviceToHost\n");
      exit(0);
    }
  cudaFree(d_Bsink);
  
  cudaFree(d_tsink);
 
  return Bsink;
}
