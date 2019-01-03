{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RecordWildCards #-}

module Main where

import Prelude hiding(putStrLn)
import Control.Monad.Except
import Control.Exception(SomeException(..),handle)
import System.Environment
import System.FilePath(splitExtension,replaceExtension,(</>))
import System.Directory(getTemporaryDirectory,doesFileExist)
import System.Exit
import System.IO(stderr,Handle,openBinaryFile,openBinaryTempFile,IOMode(..))
import Options.Applicative
import Text.RegexPR

import Text.Parsec ((<|>),(<?>))
import qualified Text.Parsec        as Parsec
import qualified Text.Parsec.String as Parsec

import qualified Data.Text as Text
import qualified Data.Text.IO as Text
import qualified Data.ByteString.Char8 as BS

-- import Web.VKHS.Types
-- import Web.VKHS.Error
-- import Web.VKHS.Client as Client
-- import Web.VKHS.Monad hiding (catch)
-- import Web.VKHS.API as API
import Web.VKHS.Imports
import Web.VKHS

import Util

env_access_token = "VKQ_ACCESS_TOKEN"

data MusicOptions = MusicOptions {
    m_list_music :: Bool
  , m_search_string :: String
  , m_name_format :: String
  , m_output_format :: String
  , m_out_dir :: Maybe String
  , m_records_id :: [String]
  , m_skip_existing :: Bool
  } deriving(Show)

-- Open file. Return filename and handle. Don't open file if it exists
openFileMR :: MusicOptions -> MusicRecord -> IO (FilePath, Maybe Handle)
openFileMR mo@MusicOptions{..} mr@MusicRecord{..} =
  case m_out_dir of
    Nothing -> do
      let (_,ext) = splitExtension (mr_url_str)
      temp <- getTemporaryDirectory
      (fp,h) <- openBinaryTempFile temp ("vkqmusic"++ext)
      return (fp, Just h)
    Just odir -> do
      let (_,ext) = splitExtension mr_url_str
      let name = mr_format m_output_format mr
      let name' = replaceExtension name (takeWhile (/='?') ext)
      let fp =  (odir </> name')
      e <- doesFileExist fp
      case (e && m_skip_existing) of
        True -> do
          return (fp,Nothing)
        False -> do
          handle (\(_::SomeException) -> do
              Text.hPutStrLn stderr ("Failed to open file " <> tpack fp)
              return (fp, Nothing)
            ) $ do
            h <- openBinaryFile fp WriteMode
            return (fp,Just h)


data UserOptions = UserOptions {
    u_queryString :: String
  } deriving(Show)

data WallOptions = WallOptions {
    w_woid :: String
  } deriving(Show)

data GroupOptions = GroupOptions {
    g_search_string :: String
  , g_output_format :: String
  } deriving(Show)

-- | Options to query VK database
data DBOptions = DBOptions {
    db_countries :: Bool
  , db_cities :: Bool
  } deriving(Show)

data APIOptions = APIOptions {
    a_method :: String
  , a_args :: [String]
  , a_pretty :: Bool
  } deriving(Show)

data LoginOptions = LoginOptions {
    l_eval :: Bool
  } deriving(Show)

data PhotoOptions = PhotoOptions {
    p_listAlbums :: Bool
  , p_uploadServer :: Bool
  , p_setUserPhoto :: Bool
  , p_userPhoto :: String
  } deriving(Show)

data Options
  = Login { genOpts :: GenericOptions, loginOpts :: LoginOptions }
  | API { genOpts :: GenericOptions, apiOpts :: APIOptions }
  | Music { genOpts :: GenericOptions, musicOpts :: MusicOptions }
  | UserQ { genOpts :: GenericOptions, userOpts :: UserOptions }
  | WallQ { genOpts :: GenericOptions, wallOpts :: WallOptions }
  | GroupQ { genOpts :: GenericOptions, groupOpts :: GroupOptions }
  | DBQ { genOpts :: GenericOptions, dbOpts :: DBOptions }
  | Photo { genOpts :: GenericOptions, photoOpts :: PhotoOptions }
  deriving(Show)

toMaybe :: (Functor f) => f String -> f (Maybe String)
toMaybe = fmap (\s -> if s == "" then Nothing else Just s)

--    * FIXME support --version flag
optdesc m =
  let

      -- genericOptions_ :: Parser GenericOptions
      genericOptions_ puser ppass = GenericOptions
        <$> (pure $ o_login_host defaultOptions)
        <*> (pure $ o_api_host defaultOptions)
        <*> (pure $ o_port defaultOptions)
        <*> flag Normal Debug (long "verbose" <> help "Be verbose")
        <*> (pure $ o_use_https defaultOptions)
        <*> fmap (read . tunpack) (tpack <$> strOption (value (show $ o_max_request_rate_per_sec defaultOptions) <> long "req-per-sec" <> metavar "N" <> help "Max number of requests per second"))
        <*> flag True False (long "interactive" <> help "Allow interactive queries")

        <*> (AppID <$> strOption (long "appid" <> metavar "APPID" <> value "3128877" <> help "Application ID, defaults to VKHS" ))
        <*> puser
        <*> ppass
        <*> strOption (short 'a' <> m <> metavar "ACCESS_TOKEN" <>
              help ("Access token. Honores " ++ env_access_token ++ " environment variable"))
        <*> strOption (long "access-token-file" <> value (l_access_token_file defaultOptions) <> metavar "FILE" <>
              help ("Filename to store actual access token, should be used to pass its value between sessions"))
        <*> pure mempty

      genericOptions = genericOptions_
        (strOption (value "" <> long "user" <> metavar "USER" <> help "User name or email"))
        (strOption (value "" <> long "pass" <> metavar "PASS" <> help "User password"))

      genericOptions_login = genericOptions_
        (argument str (metavar "USER" <> help "User name or email" <> value ""))
        (argument str (metavar "PASS" <> help "User password" <> value ""))


      api_cmd = (info (API <$> genericOptions <*> (APIOptions
        <$> argument str (metavar "METHOD" <> help "Method name")
        <*> many (argument str (metavar "PARAMS" <> help "Method arguments, KEY=VALUE[,KEY2=VALUE2[,,,]]"))
        <*> switch (long "pretty" <> help "Pretty print resulting JSON")))
            ( progDesc "Call VK API method" ))

  in hsubparser (
       command "login" (info (Login <$> genericOptions_login <*> (LoginOptions
      <$> flag False True (long "eval" <> help "Print in shell-friendly format")
      ))
      ( progDesc "Login and print access token" ))
    <> command "call" api_cmd
    <> command "api" api_cmd
    <> command "music" (info ( Music <$> genericOptions <*> (MusicOptions
      <$> switch (long "list" <> short 'l' <> help "List music files")
      <*> strOption
        ( metavar "STR"
        <> long "query" <> short 'q' <> value [] <> help "Query string")
      <*> strOption
        ( metavar "FORMAT"
        <> short 'f'
        <> value "%i %U\t%t"
        <> help "Listing format, supported tags: %i %o %a %t %d %u"
        )
      <*> strOption
        ( metavar "FORMAT"
        <> short 'F'
        <> value "%i_%a_%t"
        <> help ("Output format, supported tags:" ++ (listTags mr_tags))
        )
      <*> toMaybe (strOption (metavar "DIR" <> short 'o' <> help "Output directory" <> value ""))
      <*> many (argument str (metavar "RECORD_ID" <> help "Download records"))
      <*> flag False True (long "skip-existing" <> help "Don't download existing files")
      ))
      ( progDesc "List or download music files"))

    <> command "user" (info ( UserQ <$> genericOptions <*> (UserOptions
      <$> strOption (long "query" <> short 'q' <> help "String to query")
      ))
      ( progDesc "Extract various user information"))

    <> command "wall" (info ( WallQ <$> genericOptions <*> (WallOptions
      <$> strOption (long "id" <> short 'i' <> help "Owner id")
      ))
      ( progDesc "Extract wall information"))

    <> command "group" (info ( GroupQ <$> genericOptions <*> (GroupOptions
      <$> strOption (long "query" <> short 'q' <> value [] <> help "Group search string")
      <*> strOption
        ( metavar "FORMAT"
        <> short 'F'
        <> value "%i %m %n %u"
        <> help ("Output format, supported tags:" ++ (listTags gr_tags))
        )
      ))
      ( progDesc "Extract groups information"))

    <> command "db" (info ( DBQ <$> genericOptions <*> (DBOptions
      <$> flag False True (long "list-countries" <> help "List known countries")
      <*> flag False True (long "list-cities" <> help "List known cities")
      ))
      ( progDesc "Extract generic DB information"))

    <> command "photo" (info ( Photo <$> genericOptions <*> (PhotoOptions
      <$> flag False True (long "list-albums" <> help "List Albums")
      <*> flag False True (long "upload-server" <> help "Get upload server")
      <*> flag False True (long "set-user-photo" <> help "Set user photo")
      <*> strOption (long "photo" <> help "User photo to set" <> value "")
      ))
      ( progDesc "Photo-related queries"))
    )

main :: IO ()
main = ( do
  m <- maybe (value "") (value) <$> lookupEnv env_access_token
  o <- execParser (info (helper <*> optdesc m) (fullDesc <> header "VKontakte social network tool"))
  r <- runVK (genOpts o) (cmd o)
  case r of
    Left err -> do
      hPutStrLn stderr (printVKError err)
      exitFailure
    Right _ -> do
      return ()
  )`catch` (\(e::SomeException) -> do
    putStrLn $ Text.pack (show e)
    exitFailure
  )

{-
  ____ _     ___
 / ___| |   |_ _|
| |   | |    | |
| |___| |___ | |
 \____|_____|___|

 -}

cmd :: (MonadAPI m x s) => Options -> m (R m x) ()

-- Login
cmd (Login go LoginOptions{..}) = do
  at@AccessToken{..} <- login
  case l_eval of
    True -> liftIO $ putStrLn $ Text.pack $ printf "export %s=%s\n" env_access_token at_access_token
    False -> do
      liftIO $ putStrLn $ Text.pack at_access_token

-- API / CALL
cmd (API go APIOptions{..}) =
  let
    word :: Parsec.Parser String
    word = Parsec.try (do
            c <- Parsec.oneOf "\"'"
            ret <- Parsec.many $ Parsec.satisfy (/=c)
            Parsec.char c
            return ret)
         Parsec.<|>
            Parsec.many (Parsec.satisfy (not . flip elem (" \"=" :: String)))

    term :: Parsec.Parser (String,String)
    term = (,) <$> word <*> ((Parsec.char '=') *> word) <?> "term"

    res :: Either Parsec.ParseError [(String,String)]
    res = foldr (liftA2 (:)) (pure [])
        $ flip map a_args
        $ Parsec.runParser term () "<cmdline>"
  in do
  case res of
    Left err -> error $ "error parsing command line arguments: " <> show err
    Right pairs -> do
      x <- api a_method (map (id *** tpack) pairs)
      if a_pretty
        then do
          liftIO $ putStrLn $ jsonEncodePretty x
        else
          liftIO $ putStrLn $ jsonEncode x

cmd (Music go@GenericOptions{..} mo@MusicOptions{..}) = do
  error "VK disabled audio API since 2016/11."

-- Query groups files
cmd (GroupQ go (GroupOptions{..}))

  |not (null g_search_string) = do

    grs <- groupSearch (tpack g_search_string)

    forM_ grs $ \gr -> do
      liftIO $ printf "%s\n" (gr_format g_output_format gr)

cmd (DBQ go (DBOptions{..}))

  |db_countries = do

    cs <- getCountries

    forM_ cs $ \Country{..} -> do
      liftIO $ Text.putStrLn $ Text.concat [ tshow $ coid_id $ co_coid, "\t",  co_title]

  |db_cities = do
    error "not implemented"

cmd (Photo go PhotoOptions{..})

  |p_listAlbums = do
    (Sized cnt als) <- getAlbums Nothing
    forM_ als $ \Album{..} -> do
      liftIO $ Text.putStrLn $ Text.concat [ tshow al_id, "\t",  al_title]

  |p_uploadServer = do
    (Sized cnt als) <- getAlbums Nothing
    let album = [a | a <- als, al_id a == -7]
    case album of
      [a] -> do
        PhotoUploadServer{..} <- getPhotoUploadServer a
        liftIO $ Text.putStrLn pus_upload_url
      _ ->
        error "Ivalid album"

  |p_setUserPhoto = do
    user <- getCurrentUser
    setUserPhoto user p_userPhoto

  |otherwise = do
    error "invalid command line arguments"
