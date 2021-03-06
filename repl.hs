-- Simple s-expression repl.

import REPL.Eval
import REPL.Base
import REPL.Utils
import REPL.Types
import REPL.Parser

import Control.Monad
import Control.Monad.State.Lazy
import Control.Monad.Trans.Maybe

import qualified Data.Map as M

---

main :: IO ()
main = do
  putStrLn "Welcome to a lispy REPL. Type `h` for help."
  void $ runStateT run initialState

run :: StateT REPLState IO ()
run = forever $ do
  putStr' "> "
  input <- liftIO $ runMaybeT (getLine' >>= nest [])
  case input of
    Nothing  -> putStrLn' ">>> Too many right parentheses."
    Just []  -> return ()
    Just "r" -> registerVals
    Just "h" -> help
    Just cs  -> get >>= \rs -> do
                  output <- case rpn rs cs of
                              Left err -> return err
                              Right v  -> inject v >> return (show v)
                  putStrLn' $ ">>> " ++ output

-- | The current values of the three registers.
registerVals :: StateT REPLState IO ()
registerVals = get >>= registers >>= \rs -> do
  liftIO $ putStrLn $ "x: " ++ show (rs !! 0)
  liftIO $ putStrLn $ "y: " ++ show (rs !! 1)
  liftIO $ putStrLn $ "z: " ++ show (rs !! 2)

help :: StateT REPLState IO ()
help = get >>= builtinMap >>= \bs -> liftIO $ do
  let names = M.foldr (\f acc -> funcName f : acc) [] bs
  putStrLn "Lispy REPL Help"
  putStrLn "Available functions:"
  putStrLn $ "  [ " ++ unwords names ++ " ]"
  putStrLn "Other commands:"
  putStrLn " x -> Use the x register."
  putStrLn " y -> Use the y register."
  putStrLn " z -> Use the z register."
  putStrLn " r -> View the current values of all registers."

rpn :: REPLState -> String -> Either String Value
rpn rs s = case parseExp rs s of
          Left err   -> Left $ "Syntax Error\n" ++ show err
          Right sexp -> e sexp

-- Only notes the locations of left parens.
nest :: [Int] -> String -> MaybeT IO String
nest ps line =
  case parens ps line of
    Nothing  -> MaybeT $ return Nothing
    Just []  -> return line
    Just ps' -> do
      let pad = replicate (head ps') ' '
      putStr' $ ".  " ++ pad
      input <- (('\n' : pad) ++) `fmap` getLine'
      (line ++) `fmap` nest ps' input

-- Change to record location of first char of first arg!!
-- | Can fail if there are too many right parens.
parens :: [Int] -> String -> Maybe [Int]
parens ps line = pop $ fold (1,ps,0) line
    where fold (_,ls,rs) []       = (ls,rs)
          fold (n,ls,rs) ('(':xs) = fold (n + 1, indent n xs : ls, rs) xs
          fold (n,ls,rs) (')':xs) = fold (n + 1, ls, rs + 1) xs
          fold (n,ls,rs) (_:xs)   = fold (n + 1, ls, rs) xs

-- | The position an argument should be indented to on the next line.
indent :: Int -> String -> Int
indent p []      = p
indent p (' ':_) = p
indent p ('(':_) = p - 1
indent p (_:ns)  = indent (p + 1) ns

-- | Pops a left paren off the stack for each right paren found.
pop :: ([Int],Int) -> Maybe [Int]
pop (ls,rs) | rs > length ls = Nothing
            | otherwise      = Just $ drop rs ls
