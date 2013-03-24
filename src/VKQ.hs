{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Main where

import Control.Monad
import Data.Label.Abstract
import Data.Typeable
import Data.Data
import Data.List
import Data.Maybe
import Data.Vector as V (toList)
import qualified Data.ByteString as BS
import Network.Protocol.Uri.Query
import Options.Applicative
import System.Directory
import System.Exit
import System.FilePath
import System.Environment
import System.IO
import Text.Printf
import Text.JSON
import Text.JSON.Types
-- import Text.JSON.Generic
import Text.PFormat (pformat)
import Text.Namefilter (namefilter)
import Text.Show.Pretty as PP
import Web.VKHS
import Web.VKHS.Curl
import qualified Web.VKHS.API.Aeson as A
-- import qualified Web.VKHS.API.JSON as J
import qualified Web.VKHS.API as B
import qualified Data.Aeson as A
import qualified Data.Aeson.Types as A
import Data.Aeson (FromJSON, (.:), (.:?))
import Data.Aeson.Generic as AG

data Options = Options
  { verb :: Verbosity
  , cmdOpts :: CmdOptions
  } deriving(Show)

data CmdOptions
  = Login LoginOptions
  | Call CallOptions
  | Music MusicOptions
  | UserQ UserOptions
  deriving(Show)

data LoginOptions = LoginOptions
  { appid :: String
  , username :: String
  , password :: String
  } deriving(Show)

data CallOptions = CO
  { accessToken :: String
  , method :: String
  , args :: String
  } deriving(Show)

data MusicOptions = MO
  { accessToken_m :: String
  , list_music :: Bool
  , search_string :: String
  , name_format :: String
  , output_format :: String
  , out_dir :: String
  , records_id :: [String]
  } deriving(Show)

data UserOptions = UO
  { accessToken_u :: String
  , queryString :: String
  } deriving(Show)

loginOptions :: Parser CmdOptions
loginOptions = Login <$> (LoginOptions
  <$> strOption (metavar "APPID" & short 'a' & value "3128877" & help "Application ID, defaults to VKHS" )
  <*> argument str (metavar "USER" & help "User name or email")
  <*> argument str (metavar "PASS" & help "User password"))

opts m =
  let access_token_flag = strOption (short 'a' & m & metavar "ACCESS_TOKEN" &
        help "Access token. Honores VKQ_ACCESS_TOKEN environment variable")
  in Options
  <$> flag Normal Debug (long "verbose" & help "Be verbose")
  <*> subparser (
    command "login" (info loginOptions
      ( progDesc "Login and print access token (also prints user_id and expiriration time)" ))
    & command "call" (info (Call <$> (CO
      <$> access_token_flag
      <*> argument str (metavar "METHOD" & help "Method name")
      <*> argument str (metavar "PARAMS" & help "Method arguments, KEY=VALUE[,KEY2=VALUE2[,,,]]")))
      ( progDesc "Call VK API method" ))
    & command "music" (info ( Music <$> (MO
      <$> access_token_flag
      <*> switch (long "list" & short 'l' & help "List music files")
      <*> strOption
        ( metavar "STR"
        & long "query" & short 'q' & value [] & help "Query string")
      <*> strOption
        ( metavar "FORMAT"
        & short 'f'
        & value "id %o_%i author %a title %t url %u"
        & help "Listing format, supported tags: %i %o %a %t %d %u"
        )
      <*> strOption
        ( metavar "FORMAT"
        & short 'F'
        & value "%a - %t"
        & help "FileName format, supported tags: %i %o %a %t %d %u"
        )
      <*> strOption (metavar "DIR" & short 'o' & help "Output directory" & value "")
      <*> arguments str (metavar "RECORD_ID" & help "Download records")
      ))
      ( progDesc "List or download music files"))
    & command "user" (info ( UserQ <$> (UO
      <$> access_token_flag
      <*> strOption (long "query" & short 'q' & help "String to query")
      ))
      ( progDesc "Extract various user information"))
    )

data Response a = Response a
  deriving(Show)

-- instance (FromJSON a) => FromJSON (Response a) where
--   parseJSON (A.Object v) = Response <$> (v .: "response")

instance (Data a) => FromJSON (Response [a]) where
  parseJSON (A.Object v) = do
    a <- v .: "response"
    ls <- A.withArray "response" (\v -> do
      forM (V.toList v) $ \o -> do
        case AG.fromJSON o of
          A.Success a -> return a
          A.Error s -> fail $ "FromJSON fails :" ++ s
      ) a
    return $ Response ls

  
data MusicRecord = MR
  { aid :: Int
  , owner_id :: Int
  , artist :: String
  , title :: String
  , duration :: Int
  , url :: String
  } deriving (Show, Data, Typeable)


type MusicList = Response [MusicRecord]


mr_format :: String -> MusicRecord -> String
mr_format s mr = pformat '%'
  [ ('i', show . aid)
  , ('o', show . owner_id)
  , ('a', namefilter . artist)
  , ('t', namefilter . title)
  , ('d', show . duration)
  , ('u', url)
  ] s mr


ifeither e fl fr = either fl fr e

errexit e = hPutStrLn stderr e >> exitFailure

checkRight (Left e) = hPutStrLn stderr e >> exitFailure
checkRight (Right a) = return a

-- fromJS :: (Data a) => JSValue -> IO a
-- fromJS jv = checkR . fromJSON $ jv where
--   checkR (Ok a) = return a
--   checkR (Error s) = checkRight (Left (s ++ " JSValue: " ++ (show jv)))

main :: IO ()
main = do
  m <- maybe (idm) (value) <$> lookupEnv "VKQ_ACCESS_TOKEN"
  execParser (info (opts m) idm) >>= cmd

cmd :: Options -> IO ()
cmd (Options v (Login (LoginOptions a u p))) = do
  let e = (env a u p allAccess) { verbose = v }
  ea <- login e
  ifeither ea errexit $ \(at,uid,expin) -> do
    printf "%s %s %s\n" at uid expin

cmd (Options v (Call (CO act mn args))) = do
  let e = (envcall act) { verbose = v }
  ea <- A.api e mn (fw (keyValues "," "=") args)
  ifeither ea errexit (putStrLn . show)

-- query music files
cmd (Options v (Music mo@(MO act _ q@(_:_) fmt _ _ _))) = do
  let e = (envcall act) { verbose = v }
  ea <- A.api e "audio.search" [("q",q)]
  putStrLn $ show ea
  -- MC mc <- (checkRight >=> fromJS) ea
  -- forM_ mc $ \m -> do
  --   printf "%s\n" (mr_format fmt m)

-- list available audio files 
cmd (Options v (Music mo@(MO act True [] fmt _ _ _))) = do
  let e = (envcall act) { verbose = v }
  (Right (Response (r :: [MusicRecord]))) <- A.api' e "audio.get" []
  putStrLn $ show r
  -- MC mc <- (checkRight >=> fromJS) ea
  -- forM_ mc $ \m -> do
  --   printf "%s\n" (mr_format fmt m)

cmd (Options v (Music mo@(MO act False [] _ ofmt odir []))) = do
  errexit "Music record ID is not specified (see --help)"

-- download audio files specified
cmd (Options v (Music mo@(MO act False [] _ ofmt odir rid))) = do
  let e = (envcall act) { verbose = v }
  ea <- A.api e "audio.getById" [("audios", concat $ intersperse "," rid)]
  putStrLn $ show ea
  -- (MC mc) <- (checkRight >=> fromJS) ea
  -- forM_ mc $ \m -> do
  --   (fp, h) <- openFileMR odir ofmt m
  --   r <- vk_curl_file e (url m) $ \ bs -> do
  --     BS.hPut h bs
  --   checkRight r
  --   printf "%d_%d\n" (owner_id m) (aid m)
  --   printf "%s\n" (title m)
  --   printf "%s\n" fp

cmd (Options v (UserQ uo@(UO act qs))) = do
  let e = (envcall act) { verbose = v }
  print qs
  ea <- A.api e "users.search" [("q",qs),("fields","uid,first_name,last_name,photo,education")]
  putStrLn $ show ea
  -- ae <- checkRight ea
  -- processUQ uo ae

type NameFormat = String

openFileMR :: FilePath -> NameFormat -> MusicRecord -> IO (FilePath, Handle)
openFileMR [] _ m = do
  let (_,ext) = splitExtension (url m)
  temp <- getTemporaryDirectory
  (fp,h) <- openBinaryTempFile temp ("vkqmusic"++ext)
  return (fp,h)
openFileMR dir fmt m = do
  let (_,ext) = splitExtension (url m)
  let name = mr_format fmt m
  let name' = replaceExtension name ext
  let fp =  (dir </> name') 
  h <- openBinaryFile fp WriteMode
  return (fp,h)

-- data Collection a = MC {
--   response :: [a]
--   } deriving (Show,Data,Typeable)

-- processMC :: MusicOptions -> Collection MusicRecord -> IO ()
-- processMC (MO _ _ _) (MC r) = do
--   forM_ r $ \m -> do
--     printf "%d_%d|%s|%s|%s\n" (owner_id m) (aid m) (artist m) (title m) (url m)

-- processMC (MO _ rid False) (MC r) = do
--   print r

data UserRecord = UR
  { uid :: Int
  , first_name :: String
  , last_name :: String
  , photo :: String
  , university :: Maybe Int
  , university_name :: Maybe String
  , faculty :: Maybe Int
  , faculty_name :: Maybe String
  , graduation :: Maybe Int
  } deriving(Show,Data,Typeable)

parseUsers :: JSValue -> Maybe [JSValue]
parseUsers (JSObject (JSONObject [("response",(JSArray a))])) = Just a
parseUsers _ = Nothing

processUQ :: UserOptions -> JSValue -> IO ()
processUQ (UO _ _) j = do
  -- let (Just u) = parseUsers j
  -- a <- fromJS (u !! 1)
  -- print $ show (a :: UserRecord)
  print $ show $ j


