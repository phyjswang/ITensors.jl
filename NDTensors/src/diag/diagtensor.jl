const DiagTensor{ElT,N,StoreT,IndsT} = Tensor{ElT,N,StoreT,IndsT} where {StoreT<:Diag}
const NonuniformDiagTensor{ElT,N,StoreT,IndsT} =
  Tensor{ElT,N,StoreT,IndsT} where {StoreT<:NonuniformDiag}
const UniformDiagTensor{ElT,N,StoreT,IndsT} =
  Tensor{ElT,N,StoreT,IndsT} where {StoreT<:UniformDiag}

function diag(tensor::DiagTensor)
  tensor_diag = NDTensors.similar(dense(typeof(tensor)), (diaglength(tensor),))
  # TODO: Define `eachdiagindex`.
  diagview(tensor_diag) .= diagview(tensor)
  return tensor_diag
end

IndexStyle(::Type{<:DiagTensor}) = IndexCartesian()

# TODO: this needs to be better (promote element type, check order compatibility,
# etc.
function convert(::Type{<:DenseTensor{ElT,N}}, T::DiagTensor{ElT,N}) where {ElT<:Number,N}
  return dense(T)
end

convert(::Type{Diagonal}, D::DiagTensor{<:Number,2}) = Diagonal(data(D))

function Array{ElT,N}(T::DiagTensor{ElT,N}) where {ElT,N}
  return array(T)
end

function Array(T::DiagTensor{ElT,N}) where {ElT,N}
  return Array{ElT,N}(T)
end

function diagview(T::NonuniformDiagTensor)
  return data(T)
end

function zeros(tensortype::Type{<:DiagTensor}, inds)
  return tensor(generic_zeros(storagetype(tensortype), mindim(inds)), inds)
end

function zeros(tensortype::Type{<:DiagTensor}, inds::Dims)
  return tensor(generic_zeros(storagetype(tensortype), mindim(inds)), inds)
end

function zeros(tensortype::Type{<:DiagTensor}, inds::Tuple{})
  return tensor(generic_zeros(storagetype(tensortype), mindim(inds)), inds)
end

# Compute the norm of Uniform diagonal tensor
# TODO: Improve this with FillArrays.jl
norm(S::UniformDiagTensor) = sqrt(mindim(S) * abs2(data(S)))

"""
getdiagindex(T::DiagTensor,i::Int)

Get the ith value along the diagonal of the tensor.
"""
getdiagindex(T::DiagTensor{<:Number}, ind::Int) = storage(T)[ind]

"""
setdiagindex!(T::DiagTensor,i::Int)

Set the ith value along the diagonal of the tensor.
"""
setdiagindex!(T::DiagTensor{<:Number}, val, ind::Int) = (storage(T)[ind] = val)

"""
setdiag(T::UniformDiagTensor,val)

Set the entire diagonal of a uniform DiagTensor.
"""
setdiag(T::UniformDiagTensor, val) = tensor(Diag(val), inds(T))

function Base.copyto!(R::DenseTensor, T::DiagTensor)
  diagview(R) .= diagview(T)
  return R
end

@propagate_inbounds function getindex(
  T::DiagTensor{ElT,N}, inds::Vararg{Int,N}
) where {ElT,N}
  if all(==(inds[1]), inds)
    return getdiagindex(T, inds[1])
  else
    return zero(eltype(ElT))
  end
end
@propagate_inbounds getindex(T::DiagTensor{<:Number,1}, ind::Int) = storage(T)[ind]
using .Expose: expose
@propagate_inbounds getindex(T::DiagTensor{<:Number,0}) = getindex(expose(storage(T)))

# Set diagonal elements
# Throw error for off-diagonal
@propagate_inbounds function setindex!(
  T::DiagTensor{<:Number,N}, val, inds::Vararg{Int,N}
) where {N}
  all(==(inds[1]), inds) || error("Cannot set off-diagonal element of Diag storage")
  setdiagindex!(T, val, inds[1])
  return T
end
@propagate_inbounds function setindex!(T::DiagTensor{<:Number,1}, val, ind::Int)
  return (storage(T)[ind] = val)
end
@propagate_inbounds setindex!(T::DiagTensor{<:Number,0}, val) = (storage(T)[1] = val)

function setindex!(T::UniformDiagTensor{<:Number,N}, val, inds::Vararg{Int,N}) where {N}
  return error("Cannot set elements of a uniform Diag storage")
end

# TODO: make a fill!! that works for uniform and non-uniform
#fill!(T::DiagTensor,v) = fill!(storage(T),v)

function dense(::Type{<:Tensor{ElT,N,StoreT,IndsT}}) where {ElT,N,StoreT<:Diag,IndsT}
  return Tensor{ElT,N,dense(StoreT),IndsT}
end

using TypeParameterAccessors: unwrap_array_type
# convert to Dense
function dense(T::DiagTensor)
  R = zeros(dense(typeof(T)), inds(T))
  diagview(R) .= diagview(T)
  return R
end

denseblocks(T::DiagTensor) = dense(T)

function permutedims!(
  R::DiagTensor{<:Number,N},
  T::DiagTensor{<:Number,N},
  perm::NTuple{N,Int},
  f::Function=(r, t) -> t,
) where {N}
  # TODO: check that inds(R)==permute(inds(T),perm)?
  diagview(R) .= f.(diagview(R), diagview(T))
  return R
end

function permutedims(
  T::DiagTensor{<:Number,N}, perm::NTuple{N,Int}, f::Function=identity
) where {N}
  R = NDTensors.similar(T)
  g(r, t) = f(t)
  permutedims!(R, T, perm, g)
  return R
end

function permutedims(
  T::UniformDiagTensor{<:Number,N}, perm::NTuple{N,Int}, f::Function=identity
) where {N}
  R = tensor(Diag(f(getdiagindex(T, 1))), permute(inds(T), perm))
  return R
end

# Version that may overwrite in-place or may return the result
function permutedims!!(
  R::NonuniformDiagTensor{<:Number,N},
  T::NonuniformDiagTensor{<:Number,N},
  perm::NTuple{N,Int},
  f::Function=(r, t) -> t,
) where {N}
  R = convert(promote_type(typeof(R), typeof(T)), R)
  permutedims!(R, T, perm, f)
  return R
end

function permutedims!!(
  R::UniformDiagTensor{ElR,N},
  T::UniformDiagTensor{ElT,N},
  perm::NTuple{N,Int},
  f::Function=(r, t) -> t,
) where {ElR,ElT,N}
  R = convert(promote_type(typeof(R), typeof(T)), R)
  R = tensor(Diag(f(getdiagindex(R, 1), getdiagindex(T, 1))), inds(R))
  return R
end

function permutedims!(
  R::DenseTensor{ElR,N}, T::DiagTensor{ElT,N}, perm::NTuple{N,Int}, f::Function=(r, t) -> t
) where {ElR,ElT,N}
  diagview(R) .= f.(diagview(R), diagview(T))
  return R
end

function permutedims!!(
  R::DenseTensor{ElR,N}, T::DiagTensor{ElT,N}, perm::NTuple{N,Int}, f::Function=(r, t) -> t
) where {ElR,ElT,N}
  RR = convert(promote_type(typeof(R), typeof(T)), R)
  permutedims!(RR, T, perm, f)
  return RR
end

# TODO: make a single implementation since this is
# the same as the version with the input types
# swapped.
function permutedims!!(
  R::DiagTensor{ElR,N}, T::DenseTensor{ElT,N}, perm::NTuple{N,Int}, f::Function=(r, t) -> t
) where {ElR,ElT,N}
  RR = convert(promote_type(typeof(R), typeof(T)), R)
  permutedims!(RR, T, perm, f)
  return RR
end

function Base.mapreduce(f, op, t1::DiagTensor, t_tail::DiagTensor...; kwargs...)
  elt = mapreduce(eltype, promote_type, (t1, t_tail...))
  if !iszero(f(zero(elt)))
    return mapreduce(f, op, array(t1), array.(t_tail)...; kwargs...)
  end
  if length(t1) > diaglength(t1)
    # Some elements are zero, account for that
    # with the initial value.
    init_kwargs = (; init=zero(elt))
  else
    init_kwargs = (;)
  end
  return mapreduce(f, op, diagview(t1), diagview.(t_tail)...; kwargs..., init_kwargs...)
end

function Base.show(io::IO, mime::MIME"text/plain", T::DiagTensor)
  summary(io, T)
  print_tensor(io, T)
  return nothing
end
