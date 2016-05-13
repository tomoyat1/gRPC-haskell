module Network.GRPC.Unsafe.ByteBuffer where

#include <grpc/grpc.h>
#include <grpc/impl/codegen/slice.h>
#include <grpc/impl/codegen/compression_types.h>
#include <grpc/impl/codegen/slice_buffer.h>

#include <grpc_haskell.h>

{#import Network.GRPC.Unsafe.Slice#}
import Control.Exception (bracket)
import qualified Data.ByteString as B
import Foreign.Ptr
import Foreign.C.Types
import Foreign.Storable

{#enum grpc_compression_algorithm as GRPCCompressionAlgorithm
  {underscoreToCase} deriving (Eq) #}

-- | Represents a pointer to a gRPC byte buffer containing 1 or more 'Slice's.
-- Must be destroyed manually with 'grpcByteBufferDestroy'.
{#pointer *grpc_byte_buffer as ByteBuffer newtype #}

--Trivial Storable instance because 'ByteBuffer' type is a pointer.
instance Storable ByteBuffer where
  sizeOf (ByteBuffer r) = sizeOf r
  alignment (ByteBuffer r) = alignment r
  peek p = fmap ByteBuffer (peek (castPtr p))
  poke p (ByteBuffer r) = poke (castPtr p) r

--TODO: When I switched this to a ForeignPtr with a finalizer, I got errors
--about freeing un-malloced memory. Calling the same destroy function by hand
--works fine in the same code, though. Until I find a workaround, going to free
--everything by hand.

-- | Represents a pointer to a ByteBufferReader. Must be destroyed manually with
-- 'byteBufferReaderDestroy'.
{#pointer *grpc_byte_buffer_reader as ByteBufferReader newtype #}

-- | Creates a pointer to a 'ByteBuffer'. This is used to receive data when
-- creating a GRPC_OP_RECV_MESSAGE op.
{#fun create_receiving_byte_buffer as ^ {} -> `Ptr ByteBuffer' id#}

{#fun destroy_receiving_byte_buffer as ^ {id `Ptr ByteBuffer'} -> `()'#}

withByteBufferPtr :: (Ptr ByteBuffer -> IO a) -> IO a
withByteBufferPtr
  = bracket createReceivingByteBuffer destroyReceivingByteBuffer

-- | Takes an array of slices and the length of the array and returns a
-- 'ByteBuffer'.
{#fun grpc_raw_byte_buffer_create as ^ {`Slice', `CULong'} -> `ByteBuffer'#}

{#fun grpc_raw_compressed_byte_buffer_create as ^
  {`Slice', `CULong', `GRPCCompressionAlgorithm'} -> `ByteBuffer'#}

{#fun grpc_byte_buffer_copy as ^ {`ByteBuffer'} -> `ByteBuffer'#}

{#fun grpc_byte_buffer_length as ^ {`ByteBuffer'} -> `CULong'#}

{#fun grpc_byte_buffer_destroy as ^ {`ByteBuffer'} -> `()'#}

{#fun byte_buffer_reader_create as ^ {`ByteBuffer'} -> `ByteBufferReader'#}

{#fun byte_buffer_reader_destroy as ^ {`ByteBufferReader'} -> `()'#}

{#fun grpc_byte_buffer_reader_next as ^
  {`ByteBufferReader', `Slice'} -> `CInt'#}

-- | Returns a 'Slice' containing the entire contents of the 'ByteBuffer' being
-- read by the given 'ByteBufferReader'.
{#fun grpc_byte_buffer_reader_readall_ as ^ {`ByteBufferReader'} -> `Slice'#}

{#fun grpc_raw_byte_buffer_from_reader as ^
  {`ByteBufferReader'} -> `ByteBuffer'#}

withByteStringAsByteBuffer :: B.ByteString -> (ByteBuffer -> IO a) -> IO a
withByteStringAsByteBuffer bs f = do
  bracket (byteStringToSlice bs) freeSlice $ \slice -> do
    bracket (grpcRawByteBufferCreate slice 1) grpcByteBufferDestroy f

copyByteBufferToByteString :: ByteBuffer -> IO B.ByteString
copyByteBufferToByteString bb = do
  bracket (byteBufferReaderCreate bb) byteBufferReaderDestroy $ \bbr -> do
    bracket (grpcByteBufferReaderReadall bbr) freeSlice sliceToByteString
