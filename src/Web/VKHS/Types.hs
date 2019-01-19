{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE RecordWildCards #-}
module Web.VKHS.Types where

import qualified Data.Text.IO as Text
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import qualified Data.ByteString.Char8 as ByteString
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import qualified Data.Aeson.Encode.Pretty as Aeson
import qualified Network.Shpider.Forms as Shpider
import qualified Data.List as List

import Data.Time (secondsToDiffTime,NominalDiffTime(..),UTCTime(..),diffUTCTime)
import Network.URI(URI(..))
import Web.VKHS.Imports

-- | AccessToken is a authentication data, required by all VK API
-- functions. It is a tuple of access_token, user_id, expires_in fields,
-- returned by login procedure.
--
-- See http://vk.com/developers.php?oid=-1&p=Авторизация_клиентских_приложений
-- (in Russian) for more details
--
-- See also 'modifyAccessToken' and 'readInitialAccessToken'
data AccessToken = AccessToken {
    at_access_token :: String
  , at_user_id :: String
  , at_expires_in :: String
  } deriving(Read, Show, Eq, Ord)

-- | Access rigth to request from VK.
-- See API docs http://vk.com/developers.php?oid=-1&p=Права_доступа_приложений (in
-- Russian) for details
data AccessRight
  = Notify  -- Пользователь разрешил отправлять ему уведомления.
  | Friends -- Доступ к друзьям.
  | Photos  -- Доступ к фотографиям.
  | Audio   -- Доступ к аудиозаписям.
  | Video   -- Доступ к видеозаписям.
  | Docs    -- Доступ к документам.
  | Notes   -- Доступ заметкам пользователя.
  | Pages   -- Доступ к wiki-страницам.
  | Status  -- Доступ к статусу пользователя.
  | Offers  -- Доступ к предложениям (устаревшие методы).
  | Questions   -- Доступ к вопросам (устаревшие методы).
  | Wall    -- Доступ к обычным и расширенным методам работы со стеной.
            -- Внимание, данное право доступа недоступно для сайтов (игнорируется при попытке авторизации).
  | Groups  -- Доступ к группам пользователя.
  | Messages    -- (для Standalone-приложений) Доступ к расширенным методам работы с сообщениями.
  | Notifications   -- Доступ к оповещениям об ответах пользователю.
  | Stats   -- Доступ к статистике групп и приложений пользователя, администратором которых он является.
  | Ads     -- Доступ к расширенным методам работы с рекламным API.
  | Offline -- Доступ к API в любое время со стороннего сервера.
  deriving(Show, Eq, Ord, Enum)

toUrlArg :: [AccessRight] -> String
toUrlArg = List.intercalate "," . map (map toLower . show)


allAccess :: [AccessRight]
allAccess =
  [
  --   Notify
    Friends
  , Photos
  , Audio
  , Video
  , Docs
  , Notes
  -- , Pages
  , Status
  , Offers
  , Questions
  , Wall
  , Groups
  , Messages
  , Notifications
  , Stats
  -- , Ads
  -- , Offline
  ]

newtype AppID = AppID { aid_string :: String }
  deriving(Show, Eq, Ord)

-- | JSON wrapper.
--
--    * FIXME  Implement full set of helper functions
data JSON = JSON { js_aeson :: Aeson.Value }
  deriving(Show, Read, Data, Typeable, Eq)

-- | Encode JSON to strict Char8 ByteStirng
jsonEncodeBS :: JSON -> ByteString
jsonEncodeBS JSON{..} = ByteString.concat $ toChunks $ Aeson.encode js_aeson

-- | Encode JSON to Text
jsonEncode :: JSON -> Text
jsonEncode JSON{..} = Text.decodeUtf8 $ ByteString.concat $ toChunks $ Aeson.encode js_aeson

-- | Encode JSON to strict Char8 ByteString using pretty-style formatter
jsonEncodePrettyBS :: JSON -> ByteString
jsonEncodePrettyBS JSON{..} = ByteString.concat $ toChunks $ Aeson.encodePretty js_aeson

-- | Encode JSON to Text using pretty-style formatter
jsonEncodePretty :: JSON -> Text
jsonEncodePretty JSON{..} = Text.decodeUtf8 $ ByteString.concat $ toChunks $ Aeson.encodePretty js_aeson

-- | Utility function to parse ByteString into JSON object
decodeJSON :: ByteString -> Either Text JSON
decodeJSON bs = do
  case Aeson.eitherDecode (fromStrict bs) of
    Left err -> Left (tpack err)
    Right js -> Right (JSON js)

instance FromJSON JSON where
  parseJSON v = return $ JSON v

parseJSON :: (Aeson.FromJSON a) => JSON -> Either Text a
parseJSON j = either (Left . tpack) Right $ Aeson.parseEither Aeson.parseJSON (js_aeson j)

data Form = Form {
    form_title :: String
  , form :: Shpider.Form
  } deriving(Show,Eq)

data FilledForm = FilledForm {
    fform_title :: String
  , fform :: Shpider.Form
  } deriving(Show,Eq)


-- | Generic parameters of the VK execution. For accessing from VK runtime, use
-- `getGenericOptions` function
data GenericOptions = GenericOptions {
    o_login_host :: String
  , o_api_host :: String
  , o_port :: Int
  , o_verbosity :: Verbosity
  , o_use_https :: Bool
  , o_max_request_rate_per_sec :: Rational
  -- ^ How many requests per second is allowed
  , o_allow_interactive :: Bool

  , l_rights :: [AccessRight]
  -- ^ Access Rights to be requested at login
  , l_appid :: AppID
  , l_username :: String
  -- ^ VK user name, (typically, an email). Empty string means no value is given
  , l_password :: String
  -- ^ VK password. Empty string means no value is given
  --    * FIXME Hide plain-text passwords
  , l_access_token :: String
  -- ^ Initial access token, empty means 'not set'. Has higher precedence than
  -- l_access_token_file
  , l_access_token_file :: FilePath
  -- ^ Filename to store actual access token, should be used to pass its value
  -- between sessions
  , l_cookies_file :: FilePath
  -- ^ File to load/save cookies for storing them between program runs. Empty
  -- means 'not set.'
  -- , l_api_cache_time :: DiffTime
  } deriving(Show)

defaultOptions :: GenericOptions
defaultOptions = GenericOptions {
    o_login_host = "oauth.vk.com"
  , o_api_host = "api.vk.com"
  , o_port = 443
  , o_verbosity = Normal
  , o_use_https = True
  , o_max_request_rate_per_sec = 2
  , o_allow_interactive = True

  , l_rights = allAccess
  , l_appid  = AppID "3128877"
  , l_username = ""
  , l_password = ""
  , l_access_token = ""
  , l_access_token_file = ".vkhs-access-token"
  , l_cookies_file = ".vkhs-cookies"
  -- , l_api_cache_time = realToFrac $ secondsToDiffTime 60
  }

class ToGenericOptions s where
  toGenericOptions :: s -> GenericOptions

data Verbosity = Normal | Trace | Debug
  deriving(Enum,Eq,Ord,Show)


type MethodName = String
type MethodArgs = [(String, Text)]


data UploadRecord = UploadRecord {
    upl_server :: Integer
  , upl_photo :: Text
  , upl_hash :: Text
  } deriving(Show, Data, Typeable)

instance FromJSON UploadRecord where
  parseJSON = Aeson.withObject "UploadRecord" $ \o ->
    UploadRecord
      <$>  (o .: "server")
      <*>  (o .: "photo")
      <*>  (o .: "hash")

data HRef = HRef { href :: Text }
  deriving(Show, Read, Eq, Data, Typeable)

instance FromJSON HRef where
  parseJSON j = HRef <$> Aeson.parseJSON j


data APIError =
    APIInvalidJSON MethodName JSON Text
  | APIUnhandledError MethodName APIErrorRecord Text
  | APIUnexpected MethodName Text
  deriving(Show)


-- | Wrapper for common error codes returned by the VK API
data APIErrorCode =
    AccessDenied
  | NotLoggedIn
  | TooManyRequestsPerSec
  | ErrorCode Scientific
  -- ^ Other codes go here
  deriving(Show,Eq,Ord)

instance FromJSON APIErrorCode where
  parseJSON = Aeson.withScientific "ErrorCode" $ \n ->
    case n of
      5 -> return NotLoggedIn
      6 -> return TooManyRequestsPerSec
      15 -> return AccessDenied
      x -> return (ErrorCode x)

-- | Top-level error description, returned by VK API
data APIErrorRecord = APIErrorRecord
  { er_code :: APIErrorCode
  , er_msg :: Text
  } deriving(Show)

instance FromJSON APIErrorRecord where
  parseJSON = Aeson.withObject "ErrorRecord" $ \o ->
    APIErrorRecord
      <$> (o .: "error_code")
      <*> (o .: "error_msg")

-- | TODO: Move to Login/Types.hs
data LoginError =
    LoginNoAction
  | LoginClientError ClientError
  | LoginInvalidInputs Form (Set String)
  deriving(Show,Eq)

-- | URL wrapper
-- TODO: Move to Client/Types.hs
newtype URL = URL { uri :: URI }
  deriving(Show, Eq)

-- | TODO: Move to Client/Types.hs
data ClientError =
    ErrorParseURL { euri :: Text, emsg :: String }
  | ErrorSetURL { eurl :: URL, emsg :: String }
  deriving(Show, Eq)


data Time = Time { t_utc :: UTCTime }
  deriving(Show, Read, Eq, Ord)

data DiffTime = DiffTime { dt_utc :: NominalDiffTime }
  deriving(Show, Eq, Ord)

diffTime :: Time -> Time -> DiffTime
diffTime a b = DiffTime $ diffUTCTime (t_utc a) (t_utc b)

class (MonadCont m, MonadReader (r -> m r) m) => MonadVK m r s | m -> s where
  getVKState :: m s
  putVKState :: s -> m ()

modifyVKState :: MonadVK m r s => (s -> s) -> m ()
modifyVKState f = getVKState >>= putVKState . f

-- | Store early exit handler in the reader monad, run the computation @m@
catchVK :: (MonadVK m r s) => m r -> m r
catchVK m = do
  callCC $ \k -> do
    local (const k) m

raiseVK :: (MonadVK m r s) => ((a -> m b) -> r) -> m a
raiseVK z = callCC $ \k -> do
  err <- ask
  _ <- err (z k)
  undefined

terminate :: (MonadVK m r s) => r -> m a
terminate r = do
  err <- ask
  _ <- err r
  undefined

-- getGenericOptions :: (MonadState s m, ToGenericOptions s) => m GenericOptions
-- getGenericOptions = gets toGenericOptions


