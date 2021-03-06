module Network.IMAP.Parsers.Utils where

import Network.IMAP.Types

import Data.Attoparsec.ByteString
import qualified Data.Attoparsec.ByteString as AP
import Data.Word8
import qualified Data.Text as T
import Data.Text.Encoding (decodeUtf8)
import qualified Data.ByteString.Char8 as BSC
import qualified Data.ByteString as BS
import Data.Either.Combinators (rightToMaybe)
import Control.Monad (liftM)

eatUntilClosingParen :: Parser BSC.ByteString
eatUntilClosingParen = scan 0 hadClosedAllParens <* word8 _parenright

hadClosedAllParens :: Int -> Word8 -> Maybe Int
hadClosedAllParens openingParenCount char
  | char == _parenright =
    if openingParenCount == 1
      then Nothing
      else Just $ openingParenCount - 1
  | char == _parenleft = Just $ openingParenCount + 1
  | otherwise =  Just openingParenCount


parseEmailList :: Parser [EmailAddress]
parseEmailList = string "(" *> parseEmail `sepBy` word8 _space <* string ")"

parseEmail :: Parser EmailAddress
parseEmail = do
  string "(\""
  label <- nilOrValue $ AP.takeWhile1 (/= _quotedbl)
  string "\" NIL \""

  emailUsername <- AP.takeWhile1 (/= _quotedbl)
  string "\" \""
  emailDomain <- AP.takeWhile1 (/= _quotedbl)
  string "\")"
  let fullAddr = decodeUtf8 $ BSC.concat [emailUsername, "@", emailDomain]

  return $ EmailAddress (liftM decodeUtf8 label) fullAddr

nilOrValue :: Parser a -> Parser (Maybe a)
nilOrValue parser = rightToMaybe <$> AP.eitherP (string "NIL") parser

parseQuotedText :: Parser T.Text
parseQuotedText = do
  word8 _quotedbl
  date <- AP.takeWhile1 (/= _quotedbl)
  word8 _quotedbl

  return . decodeUtf8 $ date

parseNameAttribute :: Parser NameAttribute
parseNameAttribute = do
  string "\\"
  name <- AP.takeWhile1 isAtomChar
  return $ case name of
          "Noinferiors" -> Noinferiors
          "Noselect" -> Noselect
          "Marked" -> Marked
          "Unmarked" -> Unmarked
          "HasNoChildren" -> HasNoChildren
          _ -> OtherNameAttr $ decodeUtf8 name

parseListLikeResp :: BSC.ByteString -> Parser UntaggedResult
parseListLikeResp prefix = do
  string prefix
  string " ("
  nameAttributes <- parseNameAttribute `sepBy` word8 _space

  string ") \""
  delimiter <- liftM (decodeUtf8 . BS.singleton) AP.anyWord8
  string "\" "
  name <- liftM decodeUtf8 $ AP.takeWhile1 (/= _cr)

  let actualName = T.dropAround (== '"') name
  return $ ListR nameAttributes delimiter actualName

isAtomChar :: Word8 -> Bool
isAtomChar c = isLetter c 
            || isNumber c 
            || c == _hyphen 
            || c == _quotedbl 
            || c == _period 
            || c == _plus 
            || c == _dollar
            || c == _ampersand
            || c == _quotesingle
            || c == _comma
            || c == _hyphen
            || c == _period
            || c == _slash
            || (c >= 0x3a && c <= 0x3c)
            || (c >= 0x3e && c <= 0x40)
            || c == _backslash
            || (c >= 0x5e && c <= 0x60)
            || c == _tilde

toInt :: BSC.ByteString -> Either ErrorMessage Int
toInt bs = if null parsed
    then Left errorMsg
    else Right . fst . head $ parsed
  where parsed = reads $ BSC.unpack bs
        errorMsg = T.concat ["Count not parse '", decodeUtf8 bs, "' as an integer"]

parseNumber :: (Int -> a) -> BSC.ByteString ->
  BSC.ByteString -> Parser (Either ErrorMessage a)
parseNumber constructor prefix postfix = do
  if not . BSC.null $ prefix
    then string prefix <* word8 _space
    else return BSC.empty
  number <- takeWhile1 isDigit
  if not . BSC.null $ postfix
    then word8 _space *> string postfix
    else return BSC.empty

  return $ liftM constructor (toInt number)
