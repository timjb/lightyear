module Json

import Lightyear.Core
import Lightyear.Combinators
import Lightyear.Strings

import Data.SortedMap

%access public

data JsonValue = JsonString String
               | JsonNumber Float
               | JsonBool Bool
               | JsonNull
               | JsonArray (List JsonValue)
               | JsonObject (SortedMap String JsonValue)

hex : Parser Int
hex = do
  c <- map (ord . toUpper) $ satisfy isHexDigit
  pure $ if c >= ord '0' && c <= ord '9' then c - ord '0'
                                         else 10 + c - ord 'A'

hexQuad : Parser Int
hexQuad = do
  a <- hex
  b <- hex
  c <- hex
  d <- hex
  pure $ a * 4096 + b * 256 + c * 16 + d

specialChar : Parser Char
specialChar = do
  c <- satisfy (const True)
  case c of
    '"'  => pure '"'
    '\\' => pure '\\'
    '/'  => pure '/'
    'b'  => pure '\b'
    'f'  => pure '\f'
    'n'  => pure '\n'
    'r'  => pure '\r'
    't'  => pure '\t'
    'u'  => map chr hexQuad
    _    => satisfy (const False) <?> "expected special char"

jsonString' : Parser (List Char)
jsonString' = (char '"' $!> pure Prelude.List.Nil) <|> do
  c <- satisfy (/= '"')
  if (c == '\\') then map (::) specialChar <$> jsonString'
                 else map (c ::) jsonString'

jsonString : Parser String
jsonString = char '"' $> map pack jsonString' <?> "JSON string"

-- inspired by Haskell's Data.Scientific module
record Scientific : Type where
  MkScientific : (coefficient : Integer) ->
                 (exponent : Integer) -> Scientific

scientificToFloat : Scientific -> Float
scientificToFloat (MkScientific c e) = fromInteger c * exp
  where exp = if e < 0 then 1 / pow 10 (fromIntegerNat (- e))
                       else pow 10 (fromIntegerNat e)

parseScientific : Parser Scientific
parseScientific = do sign <- maybe 1 (const (-1)) `map` opt (char '-')
                     digits <- some digit
                     hasComma <- isJust `map` opt (char '.')
                     decimals <- if hasComma then some digit else pure Prelude.List.Nil
                     hasExponent <- isJust `map` opt (char 'e')
                     exponent <- if hasExponent then integer else pure 0
                     pure $ MkScientific (sign * fromDigits (digits ++ decimals))
                                         (exponent - cast (length decimals))
  where fromDigits : List (Fin 10) -> Integer
        fromDigits = foldl (\a, b => 10 * a + cast b) 0

jsonNumber : Parser Float
jsonNumber = map scientificToFloat parseScientific

jsonBool : Parser Bool
jsonBool  =  (char 't' >! string "rue"  $> return True)
         <|> (char 'f' >! string "alse" $> return False) <?> "JSON Bool"

jsonNull : Parser ()
jsonNull = (char 'n' >! string "ull" >! return ()) <?> "JSON Null"

mutual
  jsonArray : Parser (List JsonValue)
  jsonArray = char '[' $!> (jsonValue `sepBy` (char ',')) <$ char ']'

  keyValuePair : Parser (String, JsonValue)
  keyValuePair = do
    key <- space $> jsonString <$ space
    char ':'
    value <- jsonValue
    pure (key, value)

  jsonObject : Parser (SortedMap String JsonValue)
  jsonObject = map fromList (char '{' >! (keyValuePair `sepBy` char ',') <$ char '}')

  jsonValue' : Parser JsonValue
  jsonValue' =  (map JsonString jsonString)
            <|> (map JsonNumber jsonNumber)
            <|> (map JsonBool   jsonBool)
            <|> (pure JsonNull <$ jsonNull)
            <|>| map JsonArray  jsonArray
            <|>| map JsonObject jsonObject

  jsonValue : Parser JsonValue
  jsonValue = space $> jsonValue' <$ space

jsonToplevelValue : Parser JsonValue
jsonToplevelValue = (map JsonArray jsonArray) <|> (map JsonObject jsonObject)
