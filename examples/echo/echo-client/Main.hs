{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE LambdaCase        #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedLists   #-}
{-# OPTIONS_GHC -fno-warn-missing-signatures #-}
{-# OPTIONS_GHC -fno-warn-unused-binds       #-}

import           Control.Concurrent.Async
import           Control.Monad
import qualified Data.ByteString.Lazy                      as BL
import           Data.Protobuf.Wire.Class
import           Data.Protobuf.Wire.Types
import qualified Data.Text                                 as T
import           Data.Word
import           GHC.Generics                              (Generic)
import           Network.GRPC.LowLevel
import qualified Network.GRPC.LowLevel.Client.Unregistered as U
import           System.Random                             (randomRIO)

echoMethod = MethodName "/echo.Echo/DoEcho"
addMethod = MethodName "/echo.Add/DoAdd"

_unregistered c = U.clientRequest c echoMethod 1 "hi" mempty

regMain = withGRPC $ \g ->
  withClient g (ClientConfig "localhost" 50051 [] Nothing) $ \c -> do
  rm <- clientRegisterMethodNormal c echoMethod
  replicateM_ 100000 $ clientRequest c rm 5 "hi" mempty >>= \case
    Left e -> fail $ "Got client error: " ++ show e
    Right r
      | rspBody r == "hi" -> return ()
      | otherwise -> fail $ "Got unexpected payload: " ++ show r

-- NB: If you change these, make sure to change them in the server as well.
-- TODO: Put these in a common location (or just hack around it until CG is working)
data EchoRequest = EchoRequest {message :: T.Text} deriving (Show, Eq, Ord, Generic)
instance Message EchoRequest
data AddRequest = AddRequest {addX :: Fixed Word32, addY :: Fixed Word32} deriving (Show, Eq, Ord, Generic)
instance Message AddRequest
data AddResponse = AddResponse {answer :: Fixed Word32} deriving (Show, Eq, Ord, Generic)
instance Message AddResponse

-- TODO: Create Network.GRPC.HighLevel.Client w/ request variants

highlevelMain = withGRPC $ \g ->
    withClient g (ClientConfig "localhost" 50051 [] Nothing) $ \c -> do
    rm <- clientRegisterMethodNormal c echoMethod
    rmAdd <- clientRegisterMethodNormal c addMethod
    let oneThread = replicateM_ 10000 $ body c rm rmAdd
    tids <- replicateM 4 (async oneThread)
    results <- mapM waitCatch tids
    print $ "waitCatch results: " ++ show (sequence results)
      where body c rm rmAdd = do
              let pay = EchoRequest "hi"
                  enc = BL.toStrict . toLazyByteString $ pay
              clientRequest c rm 5 enc mempty >>= \case
                Left e  -> fail $ "Got client error: " ++ show e
                Right r -> case fromByteString (rspBody r) of
                  Left e -> fail $ "Got decoding error: " ++ show e
                  Right dec
                    | dec == pay -> return ()
                    | otherwise -> fail $ "Got unexpected payload: " ++ show dec
              x <- liftM Fixed $ randomRIO (0,1000)
              y <- liftM Fixed $ randomRIO (0,1000)
              let addPay = AddRequest x y
                  addEnc = BL.toStrict . toLazyByteString $ addPay
              clientRequest c rmAdd 5 addEnc mempty >>= \case
                Left e -> fail $ "Got client error on add request: " ++ show e
                Right r -> case fromByteString (rspBody r) of
                  Left e -> fail $ "failed to decode add response: " ++ show e
                  Right dec
                    | dec == AddResponse (x + y) -> return ()
                    | otherwise -> fail $ "Got wrong add answer: " ++ show dec ++ "expected: " ++ show x ++ " + " ++ show y ++ " = " ++ show (x+y)

main :: IO ()
main = highlevelMain
