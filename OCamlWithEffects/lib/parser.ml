open Angstrom
open Ast
open List
open String

type error_message = string
type input = string

type dispatch =
  { parse_list_constructing : dispatch -> expression Angstrom.t
  ; parse_tuple : dispatch -> expression Angstrom.t
  ; parse_binary_operation : dispatch -> expression Angstrom.t
  ; parse_unary_operation : dispatch -> expression Angstrom.t
  ; parse_list : dispatch -> expression Angstrom.t
  ; parse_application : dispatch -> expression Angstrom.t
  ; parse_fun : dispatch -> expression Angstrom.t
  ; parse_conditional : dispatch -> expression Angstrom.t
  ; parse_matching : dispatch -> expression Angstrom.t
  ; parse_let_in : dispatch -> expression Angstrom.t
  ; parse_data_constructor : dispatch -> expression Angstrom.t
  ; parse_expression : dispatch -> expression Angstrom.t
  }

(* Functions for constructing expressions *)
let eliteral x = ELiteral x
let eidentifier x = EIdentifier x
let etuple head tail = ETuple (head :: tail)
let elist x = EList x
let efun variable_list expression = EFun (variable_list, expression)

let ebinary_operation operator left_operand right_operand =
  EBinaryOperation (operator, left_operand, right_operand)
;;

let edeclaration function_name variable_list expression =
  EDeclaration (function_name, variable_list, expression)
;;

let erecursivedeclaration function_name variable_list expression =
  ERecursiveDeclaration (function_name, variable_list, expression)
;;

let eif condition true_branch false_branch = EIf (condition, true_branch, false_branch)
let ematchwith expression cases = EMatchWith (expression, cases)
let eletin declaration_list body = ELetIn (declaration_list, body)

let eapplication function_expression operand_expression =
  EApplication (function_expression, operand_expression)
;;

let edata_constructor constructor_name expressions =
  EDataConstructor (constructor_name, expressions)
;;

let eunary_operation operation expression = EUnaryOperation (operation, expression)
let econstruct_list head tail = EConstructList (head, tail)
(* -------------------------------------- *)

(* Smart constructors for binary operators *)
let badd _ = Add
let bsub _ = Sub
let bmul _ = Mul
let bdiv _ = Div
let beq _ = Eq
let bneq _ = NEq
let bgt _ = GT
let bgte _ = GTE
let blt _ = LT
let blte _ = LTE
let band _ = AND
let bor _ = OR
(* --------------------------------------- *)

(* Smart constructors for unary operators *)
let uminus _ = Minus
let unot _ = Not
(* -------------------------------------- *)

(* Helpers *)
let space_predicate x = x == ' ' || x == '\n' || x == '\t' || x == '\r'
let remove_spaces = take_while space_predicate
let parens parser = remove_spaces *> char '(' *> parser <* remove_spaces <* char ')'

let parse_entity =
  fix
  @@ fun self ->
  remove_spaces
  *> (parens self
     <|> take_while1 (fun x ->
           contains "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'_" x)
     )
;;

let data_constructors = [ "Ok"; "Error"; "Some"; "None" ]
let keywords = [ "let"; "rec"; "match"; "with"; "if"; "then"; "else"; "in"; "fun"; "and" ]
(* ------- *)

(* Parsers *)
let parse_literal =
  fix
  @@ fun self ->
  remove_spaces
  *> (parens self
     <|>
     let is_digit = function
       | '0' .. '9' -> true
       | _ -> false
     in
     let parse_int_literal = take_while1 is_digit >>| int_of_string >>| fun x -> LInt x in
     let parse_string_literal =
       char '"' *> take_while (( != ) '"') <* char '"' >>| fun x -> LString x
     in
     let parse_char_literal = char '\'' *> any_char <* char '\'' >>| fun x -> LChar x in
     let parse_bool_literal =
       string "true" <|> string "false" >>| bool_of_string >>| fun x -> LBool x
     in
     let parse_unit_literal = string "()" >>| fun _ -> LUnit in
     let parse_literal =
       choice
         [ parse_int_literal
         ; parse_string_literal
         ; parse_char_literal
         ; parse_bool_literal
         ; parse_unit_literal
         ]
     in
     lift eliteral parse_literal)
;;

let parse_identifier =
  fix
  @@ fun _ ->
  remove_spaces
  *>
  let parse_identifier =
    parse_entity
    >>= fun entity ->
    if List.exists (( = ) entity) keywords || List.exists (( = ) entity) data_constructors
    then fail "Parsing error: keyword used."
    else return @@ eidentifier entity
  in
  parse_identifier
;;

let parse_tuple d =
  fix
  @@ fun self ->
  remove_spaces
  *> ((let parse_content =
         choice
           [ parens self
           ; d.parse_list_constructing d
           ; d.parse_binary_operation d
           ; d.parse_unary_operation d
           ; d.parse_list d
           ; d.parse_application d
           ; d.parse_fun d
           ; d.parse_conditional d
           ; d.parse_matching d
           ; d.parse_let_in d
           ; d.parse_data_constructor d
           ; parse_literal
           ; parse_identifier
           ]
       and separator = remove_spaces *> char ',' *> remove_spaces in
       lift2
         etuple
         (parse_content <* separator)
         (sep_by1 separator parse_content <* remove_spaces))
     <|> parens self)
;;

let parse_list d =
  fix
  @@ fun self ->
  remove_spaces
  *>
  let brackets parser = char '[' *> parser <* char ']'
  and separator = remove_spaces *> char ';' *> remove_spaces <|> remove_spaces
  and parse_content =
    choice
      [ d.parse_tuple d
      ; d.parse_list_constructing d
      ; d.parse_binary_operation d
      ; d.parse_unary_operation d
      ; self
      ; d.parse_application d
      ; d.parse_fun d
      ; d.parse_conditional d
      ; d.parse_matching d
      ; d.parse_let_in d
      ; d.parse_data_constructor d
      ; parse_literal
      ; parse_identifier
      ]
  in
  parens self
  <|> lift elist @@ brackets @@ (remove_spaces *> many (parse_content <* separator))
;;

let parse_fun d =
  fix
  @@ fun self ->
  remove_spaces
  *>
  let parse_content =
    choice
      [ d.parse_tuple d
      ; d.parse_list_constructing d
      ; d.parse_binary_operation d
      ; d.parse_unary_operation d
      ; d.parse_list d
      ; d.parse_application d
      ; self
      ; d.parse_conditional d
      ; d.parse_matching d
      ; d.parse_let_in d
      ; d.parse_data_constructor d
      ; parse_literal
      ; parse_identifier
      ]
  in
  parens self
  <|> string "fun"
      *> lift2
           efun
           (many1 parse_entity <* remove_spaces <* string "->" <* remove_spaces)
           (parse_content <* remove_spaces)
;;

(* Used in parse_declaration and parse_let_in *)
let declaration_helper constructing_function d =
  let parse_content =
    choice
      [ d.parse_tuple d
      ; d.parse_list_constructing d
      ; d.parse_binary_operation d
      ; d.parse_unary_operation d
      ; d.parse_list d
      ; d.parse_application d
      ; d.parse_fun d
      ; d.parse_conditional d
      ; d.parse_matching d
      ; d.parse_let_in d
      ; d.parse_data_constructor d
      ; parse_literal
      ; parse_identifier
      ]
  in
  lift3
    constructing_function
    parse_entity
    (many parse_entity)
    (remove_spaces *> string "=" *> parse_content)
;;

let parse_declaration d =
  fix
  @@ fun _ ->
  remove_spaces
  *> string "let"
  *> take_while1 space_predicate
  *> option "" (string "rec" <* take_while1 space_predicate)
  >>= fun parsed_rec ->
  match parsed_rec with
  | "rec" -> declaration_helper erecursivedeclaration d
  | _ -> declaration_helper edeclaration d
;;

let parse_let_in d =
  fix
  @@ fun self ->
  remove_spaces
  *>
  let parse_content =
    choice
      [ d.parse_tuple d
      ; d.parse_list_constructing d
      ; d.parse_binary_operation d
      ; d.parse_unary_operation d
      ; d.parse_list d
      ; d.parse_application d
      ; d.parse_fun d
      ; d.parse_conditional d
      ; d.parse_matching d
      ; self
      ; d.parse_data_constructor d
      ; parse_literal
      ; parse_identifier
      ]
  in
  parens self
  <|> (string "let"
       *> take_while1 space_predicate
       *> option "" (string "rec" <* take_while1 space_predicate)
      >>= fun parsed_rec ->
      lift2
        eletin
        (let separator = remove_spaces *> string "and" *> take_while1 space_predicate in
         match parsed_rec with
         | "rec" -> sep_by1 separator @@ declaration_helper erecursivedeclaration d
         | _ -> sep_by1 separator @@ declaration_helper edeclaration d)
        (remove_spaces *> string "in" *> parse_content))
;;

let parse_conditional d =
  fix
  @@ fun self ->
  remove_spaces
  *>
  let parse_content =
    choice
      [ d.parse_tuple d
      ; d.parse_list_constructing d
      ; d.parse_binary_operation d
      ; d.parse_unary_operation d
      ; d.parse_list d
      ; d.parse_application d
      ; d.parse_fun d
      ; self
      ; d.parse_matching d
      ; d.parse_let_in d
      ; d.parse_data_constructor d
      ; parse_literal
      ; parse_identifier
      ]
  in
  parens self
  <|> string "if"
      *> lift3
           eif
           parse_content
           (remove_spaces *> string "then" *> parse_content)
           (remove_spaces *> string "else" *> parse_content)
;;

let parse_matching d =
  fix
  @@ fun self ->
  remove_spaces
  *>
  let parse_content =
    choice
      [ d.parse_tuple d
      ; d.parse_list_constructing d
      ; d.parse_binary_operation d
      ; d.parse_unary_operation d
      ; d.parse_list d
      ; d.parse_application d
      ; d.parse_fun d
      ; d.parse_conditional d
      ; self
      ; d.parse_let_in d
      ; d.parse_data_constructor d
      ; parse_literal
      ; parse_identifier
      ]
  in
  parens self
  <|> string "match"
      *> lift2
           ematchwith
           parse_content
           (let parse_case =
              lift2
                (fun case action -> case, action)
                parse_content
                (remove_spaces *> string "->" *> parse_content)
            and separator = remove_spaces *> string "|" in
            remove_spaces
            *> string "with"
            *> remove_spaces
            *> (string "|" <|> remove_spaces)
            *> sep_by1 separator parse_case)
;;

let parse_binary_operation d =
  fix
  @@ fun self ->
  remove_spaces
  *>
  let multiplicative = remove_spaces *> choice [ char '*' >>| bmul; char '/' >>| bdiv ]
  and additive = remove_spaces *> choice [ char '+' >>| badd; char '-' >>| bsub ]
  and relational =
    remove_spaces
    *> choice
         [ string ">=" >>| bgte
         ; string "<=" >>| blte
         ; char '>' >>| bgt
         ; char '<' >>| blt
         ]
  and equality =
    remove_spaces *> choice [ string "=" >>| beq; string "!=" <|> string "<>" >>| bneq ]
  and logical_and = remove_spaces *> (string "&&" >>| band)
  and logical_or = remove_spaces *> (string "||" >>| bor) in
  let chainl1 expression_parser operation_parser =
    let rec go acc =
      lift2
        (fun binary_operator right_operand ->
          ebinary_operation binary_operator acc right_operand)
        operation_parser
        expression_parser
      >>= go
      <|> return acc
    in
    expression_parser >>= fun init -> go init
  in
  let ( <||> ) = chainl1 in
  let parse_content =
    choice
      [ parens self
      ; d.parse_unary_operation d
      ; d.parse_application d
      ; d.parse_conditional d
      ; d.parse_matching d
      ; d.parse_let_in d
      ; d.parse_data_constructor d
      ; parse_literal
      ; parse_identifier
      ]
  in
  parse_content
  <||> multiplicative
  <||> additive
  <||> relational
  <||> equality
  <||> logical_and
  <||> logical_or
  >>= fun result ->
  match result with
  | EBinaryOperation (_, _, _) -> return result
  | _ -> fail "Parsing error: not binary operation."
;;

let parse_application d =
  fix
  @@ fun self ->
  remove_spaces
  *> (parens self
     <|>
     let function_parser =
       choice
         [ parens @@ d.parse_fun d
         ; parens @@ d.parse_conditional d
         ; parens @@ d.parse_matching d
         ; parens @@ d.parse_let_in d
         ; parse_identifier
         ]
     and operand_parser =
       choice
         [ parens @@ d.parse_tuple d
         ; parens @@ d.parse_list_constructing d
         ; parens @@ d.parse_binary_operation d
         ; parens @@ d.parse_unary_operation d
         ; d.parse_list d
         ; parens self
         ; parens @@ d.parse_fun d
         ; parens @@ d.parse_conditional d
         ; parens @@ d.parse_matching d
         ; parens @@ d.parse_let_in d
         ; parens @@ d.parse_data_constructor d
         ; parse_literal
         ; parse_identifier
         ]
     in
     let apply_lift acc = lift (eapplication acc) operand_parser in
     let rec go acc = apply_lift acc >>= go <|> return acc in
     function_parser >>= fun init -> apply_lift init >>= fun init -> go init)
;;

let parse_data_constructor d =
  fix
  @@ fun self ->
  remove_spaces
  *>
  let parse_content =
    choice
      [ parens @@ d.parse_tuple d
      ; parens @@ d.parse_list_constructing d
      ; parens @@ d.parse_binary_operation d
      ; parens @@ d.parse_unary_operation d
      ; d.parse_list d
      ; parens @@ d.parse_application d
      ; parens @@ d.parse_fun d
      ; parens @@ d.parse_conditional d
      ; parens @@ d.parse_matching d
      ; parens @@ d.parse_let_in d
      ; parens self
      ; parse_literal
      ; parse_identifier
      ]
  in
  parens self
  <|> (lift2
         (fun constructor_name expression_list -> constructor_name, expression_list)
         parse_entity
         (many parse_content)
      >>= function
      | constructor_name, expression_list ->
        if List.exists (( = ) constructor_name) data_constructors
        then
          if List.length expression_list > 1
          then fail "Parsing error: data constructor received too many arguments."
          else return @@ edata_constructor constructor_name expression_list
        else fail "Parsing error: invalid constructor.")
;;

let parse_unary_operation d =
  fix
  @@ fun self ->
  remove_spaces
  *>
  let parse_content_minus =
    let indent = many1 (satisfy space_predicate) in
    choice
      [ parens self <|> indent *> self
      ; parens @@ d.parse_application d <|> indent *> d.parse_application d
      ; parens @@ d.parse_conditional d <|> indent *> d.parse_conditional d
      ; parens @@ d.parse_matching d <|> indent *> d.parse_matching d
      ; parens @@ d.parse_let_in d <|> indent *> d.parse_let_in d
      ; parse_literal
      ; parse_identifier
      ; parens @@ d.parse_binary_operation d
      ]
  and parse_content_not =
    choice
      [ parens @@ d.parse_binary_operation d
      ; parens self
      ; parens @@ d.parse_application d
      ; parens @@ d.parse_conditional d
      ; parens @@ d.parse_matching d
      ; parens @@ d.parse_let_in d
      ; parse_literal
      ; parse_identifier
      ]
  in
  parens self
  <|> lift2 eunary_operation (char '-' >>| uminus) parse_content_minus
  <|> lift2 eunary_operation (string "not" >>| unot) parse_content_not
;;

let parse_list_constructing d =
  fix
  @@ fun self ->
  remove_spaces
  *> (parens self
     <|>
     let separator = remove_spaces *> string "::" *> remove_spaces
     and parse_content =
       choice
         [ parens @@ d.parse_tuple d
         ; parens self
         ; parens @@ d.parse_binary_operation d
         ; d.parse_unary_operation d
         ; d.parse_list d
         ; d.parse_application d
         ; parens @@ d.parse_fun d
         ; parens @@ d.parse_conditional d
         ; parens @@ d.parse_matching d
         ; d.parse_let_in d
         ; d.parse_data_constructor d
         ; parse_literal
         ; parse_identifier
         ]
     in
     lift2 econstruct_list (parse_content <* separator) (self <|> parse_content))
;;

(* ------- *)

let parse_expression d =
  choice
    [ d.parse_tuple d
    ; d.parse_list_constructing d
    ; d.parse_binary_operation d
    ; d.parse_unary_operation d
    ; d.parse_list d
    ; d.parse_application d
    ; d.parse_fun d
    ; d.parse_conditional d
    ; d.parse_matching d
    ; d.parse_let_in d
    ; d.parse_data_constructor d
    ; parse_literal
    ; parse_identifier
    ]
;;

let default =
  { parse_list_constructing
  ; parse_tuple
  ; parse_binary_operation
  ; parse_unary_operation
  ; parse_list
  ; parse_application
  ; parse_fun
  ; parse_conditional
  ; parse_matching
  ; parse_let_in
  ; parse_data_constructor
  ; parse_expression
  }
;;

let parse_tuple = parse_tuple default
let parse_list = parse_list default
let parse_fun = parse_fun default
let parse_declaration = parse_declaration default
let parse_conditional = parse_conditional default
let parse_matching = parse_matching default
let parse_binary_operation = parse_binary_operation default
let parse_let_in = parse_let_in default
let parse_application = parse_application default
let parse_unary_operation = parse_unary_operation default
let parse_list_constructing = parse_list_constructing default
let parse_data_constructor = parse_data_constructor default
let parse_expression = parse_expression default

(* Main parsing function *)
let parse : input -> (expression list, error_message) result =
 fun program ->
  parse_string ~consume:All (many parse_declaration <* remove_spaces) program
;;

(* -------------------- TESTS -------------------- *)

(* 1 *)
let%test _ =
  parse
    "let rec factorial n acc = if n <= 1 then acc else factorial (n - 1) (acc * n)\n\
     let main = factorial 5 1 "
  = Result.ok
    @@ [ ERecursiveDeclaration
           ( "factorial"
           , [ "n"; "acc" ]
           , EIf
               ( EBinaryOperation (LTE, EIdentifier "n", ELiteral (LInt 1))
               , EIdentifier "acc"
               , EApplication
                   ( EApplication
                       ( EIdentifier "factorial"
                       , EBinaryOperation (Sub, EIdentifier "n", ELiteral (LInt 1)) )
                   , EBinaryOperation (Mul, EIdentifier "acc", EIdentifier "n") ) ) )
       ; EDeclaration
           ( "main"
           , []
           , EApplication
               ( EApplication (EIdentifier "factorial", ELiteral (LInt 5))
               , ELiteral (LInt 1) ) )
       ]
;;

(* 2 *)
let%test _ =
  parse " let main = 1 :: 2 :: [] "
  = Result.ok
    @@ [ EDeclaration
           ( "main"
           , []
           , EConstructList
               (ELiteral (LInt 1), EConstructList (ELiteral (LInt 2), EList [])) )
       ]
;;

(* 3 *)
let%test _ =
  parse " let main = true :: (false) :: [false] "
  = Result.ok
    @@ [ EDeclaration
           ( "main"
           , []
           , EConstructList
               ( ELiteral (LBool true)
               , EConstructList (ELiteral (LBool false), EList [ ELiteral (LBool false) ])
               ) )
       ]
;;

(* 4 *)
let%test _ =
  parse " let main = (10 + 20) :: [30; 4 * 10] "
  = Result.ok
    @@ [ EDeclaration
           ( "main"
           , []
           , EConstructList
               ( EBinaryOperation (Add, ELiteral (LInt 10), ELiteral (LInt 20))
               , EList
                   [ ELiteral (LInt 30)
                   ; EBinaryOperation (Mul, ELiteral (LInt 4), ELiteral (LInt 10))
                   ] ) )
       ]
;;

(* 5 *)
let%test _ =
  parse " let main = (fun x -> 'a') :: [fun _ -> 'b'] "
  = Result.ok
    @@ [ EDeclaration
           ( "main"
           , []
           , EConstructList
               ( EFun ([ "x" ], ELiteral (LChar 'a'))
               , EList [ EFun ([ "_" ], ELiteral (LChar 'b')) ] ) )
       ]
;;

(* 6 *)
let%test _ =
  parse " let main = () :: (()) :: ((())) :: (((()))) :: [] "
  = Result.ok
    @@ [ EDeclaration
           ( "main"
           , []
           , EConstructList
               ( ELiteral LUnit
               , EConstructList
                   ( ELiteral LUnit
                   , EConstructList
                       (ELiteral LUnit, EConstructList (ELiteral LUnit, EList [])) ) ) )
       ]
;;

(* 7 *)
let%test _ =
  parse " let main = [\"apple\";\n\"orange\";\n\"banana\";\n\"pear\"] "
  = Result.ok
    @@ [ EDeclaration
           ( "main"
           , []
           , EList
               [ ELiteral (LString "apple")
               ; ELiteral (LString "orange")
               ; ELiteral (LString "banana")
               ; ELiteral (LString "pear")
               ] )
       ]
;;

(* 8 *)
let%test _ =
  parse " let main = [ 'h' ; 'e' ; 'l' ; 'l' ; 'o' ] "
  = Result.ok
    @@ [ EDeclaration
           ( "main"
           , []
           , EList
               [ ELiteral (LChar 'h')
               ; ELiteral (LChar 'e')
               ; ELiteral (LChar 'l')
               ; ELiteral (LChar 'l')
               ; ELiteral (LChar 'o')
               ] )
       ]
;;

(* 9 *)
let%test _ =
  parse " let main = [1] "
  = Result.ok @@ [ EDeclaration ("main", [], EList [ ELiteral (LInt 1) ]) ]
;;

(* 10 *)
let%test _ =
  parse " let main = [] " = Result.ok @@ [ EDeclaration ("main", [], EList []) ]
;;

(* 11 *)
let%test _ =
  parse
    " let main = [let x = 5 and y = 7 in x + y; (fun t -> t - 1) 10; if (5 >= 1) then 1 \
     else 0] "
  = Result.ok
    @@ [ EDeclaration
           ( "main"
           , []
           , EList
               [ ELetIn
                   ( [ EDeclaration ("x", [], ELiteral (LInt 5))
                     ; EDeclaration ("y", [], ELiteral (LInt 7))
                     ]
                   , EBinaryOperation (Add, EIdentifier "x", EIdentifier "y") )
               ; EApplication
                   ( EFun
                       ( [ "t" ]
                       , EBinaryOperation (Sub, EIdentifier "t", ELiteral (LInt 1)) )
                   , ELiteral (LInt 10) )
               ; EIf
                   ( EBinaryOperation (GTE, ELiteral (LInt 5), ELiteral (LInt 1))
                   , ELiteral (LInt 1)
                   , ELiteral (LInt 0) )
               ] )
       ]
;;

(* 12 *)
let%test _ =
  parse
    " let main = (if x > 0 then 1 else (if x = 0 then 0 else -1)) :: [0 ; (if y > 0 then \
     1 else (if y = 0 then 0 else -1)) ; 0] "
  = Result.ok
    @@ [ EDeclaration
           ( "main"
           , []
           , EConstructList
               ( EIf
                   ( EBinaryOperation (GT, EIdentifier "x", ELiteral (LInt 0))
                   , ELiteral (LInt 1)
                   , EIf
                       ( EBinaryOperation (Eq, EIdentifier "x", ELiteral (LInt 0))
                       , ELiteral (LInt 0)
                       , EUnaryOperation (Minus, ELiteral (LInt 1)) ) )
               , EList
                   [ ELiteral (LInt 0)
                   ; EIf
                       ( EBinaryOperation (GT, EIdentifier "y", ELiteral (LInt 0))
                       , ELiteral (LInt 1)
                       , EIf
                           ( EBinaryOperation (Eq, EIdentifier "y", ELiteral (LInt 0))
                           , ELiteral (LInt 0)
                           , EUnaryOperation (Minus, ELiteral (LInt 1)) ) )
                   ; ELiteral (LInt 0)
                   ] ) )
       ]
;;

(* 13 *)
let%test _ =
  parse " let main = fun x y z -> x + y * z "
  = Result.ok
    @@ [ EDeclaration
           ( "main"
           , []
           , EFun
               ( [ "x"; "y"; "z" ]
               , EBinaryOperation
                   ( Add
                   , EIdentifier "x"
                   , EBinaryOperation (Mul, EIdentifier "y", EIdentifier "z") ) ) )
       ]
;;

(* 14 *)
let%test _ =
  parse " let main = fun _ -> 42 "
  = Result.ok @@ [ EDeclaration ("main", [], EFun ([ "_" ], ELiteral (LInt 42))) ]
;;

(* 15 *)
let%test _ =
  parse " let main = fun _ -> fun _ -> \"Hello\" "
  = Result.ok
    @@ [ EDeclaration
           ("main", [], EFun ([ "_" ], EFun ([ "_" ], ELiteral (LString "Hello"))))
       ]
;;

(* 16 *)
let%test _ =
  parse " let main = fun x y -> if x < 0 then [x;y] else [0;y] "
  = Result.ok
    @@ [ EDeclaration
           ( "main"
           , []
           , EFun
               ( [ "x"; "y" ]
               , EIf
                   ( EBinaryOperation (LT, EIdentifier "x", ELiteral (LInt 0))
                   , EList [ EIdentifier "x"; EIdentifier "y" ]
                   , EList [ ELiteral (LInt 0); EIdentifier "y" ] ) ) )
       ]
;;

(* 17 *)
let%test _ =
  parse
    " let rec matrix_mult_number matrix number =\n\
    \     let rec line_mult_number line =\n\
    \       match line with\n\
    \         | head :: tail -> (head * number) :: line_mult_number tail\n\
    \         | _ -> []\n\
    \     in\n\
    \     match matrix with\n\
    \       | head :: tail -> line_mult_number head :: matrix_mult_number tail number\n\
    \       | _ -> []"
  = Result.ok
    @@ [ ERecursiveDeclaration
           ( "matrix_mult_number"
           , [ "matrix"; "number" ]
           , ELetIn
               ( [ ERecursiveDeclaration
                     ( "line_mult_number"
                     , [ "line" ]
                     , EMatchWith
                         ( EIdentifier "line"
                         , [ ( EConstructList (EIdentifier "head", EIdentifier "tail")
                             , EConstructList
                                 ( EBinaryOperation
                                     (Mul, EIdentifier "head", EIdentifier "number")
                                 , EApplication
                                     (EIdentifier "line_mult_number", EIdentifier "tail")
                                 ) )
                           ; EIdentifier "_", EList []
                           ] ) )
                 ]
               , EMatchWith
                   ( EIdentifier "matrix"
                   , [ ( EConstructList (EIdentifier "head", EIdentifier "tail")
                       , EConstructList
                           ( EApplication
                               (EIdentifier "line_mult_number", EIdentifier "head")
                           , EApplication
                               ( EApplication
                                   (EIdentifier "matrix_mult_number", EIdentifier "tail")
                               , EIdentifier "number" ) ) )
                     ; EIdentifier "_", EList []
                     ] ) ) )
       ]
;;

(* 18 *)
let%test _ =
  parse " let main = \"Danya\", \"Ilya\" "
  = Result.ok
    @@ [ EDeclaration
           ("main", [], ETuple [ ELiteral (LString "Danya"); ELiteral (LString "Ilya") ])
       ]
;;

(* 19 *)
let%test _ =
  parse " let main = ( 123\t, \"aaa\"\t, 'b'\n, true\t, ()\t ) "
  = Result.ok
    @@ [ EDeclaration
           ( "main"
           , []
           , ETuple
               [ ELiteral (LInt 123)
               ; ELiteral (LString "aaa")
               ; ELiteral (LChar 'b')
               ; ELiteral (LBool true)
               ; ELiteral LUnit
               ] )
       ]
;;

(* 20 *)
let%test _ =
  parse " let main = (fun _ -> 1, fun _ -> 2) "
  = Result.ok
    @@ [ EDeclaration
           ( "main"
           , []
           , EFun
               ([ "_" ], ETuple [ ELiteral (LInt 1); EFun ([ "_" ], ELiteral (LInt 2)) ])
           )
       ]
;;

(* 21 *)
let%test _ =
  parse " let main = [fun _ -> 1; fun _ -> 2] "
  = Result.ok
    @@ [ EDeclaration
           ( "main"
           , []
           , EList
               [ EFun ([ "_" ], ELiteral (LInt 1)); EFun ([ "_" ], ELiteral (LInt 2)) ] )
       ]
;;

(* 22 *)
let%test _ =
  parse " let main = f (g 5, h ()) (let x = 17 and y = 6 and z = 3 in x * y / z) "
  = Result.ok
    @@ [ EDeclaration
           ( "main"
           , []
           , EApplication
               ( EApplication
                   ( EIdentifier "f"
                   , ETuple
                       [ EApplication (EIdentifier "g", ELiteral (LInt 5))
                       ; EApplication (EIdentifier "h", ELiteral LUnit)
                       ] )
               , ELetIn
                   ( [ EDeclaration ("x", [], ELiteral (LInt 17))
                     ; EDeclaration ("y", [], ELiteral (LInt 6))
                     ; EDeclaration ("z", [], ELiteral (LInt 3))
                     ]
                   , EBinaryOperation
                       ( Div
                       , EBinaryOperation (Mul, EIdentifier "x", EIdentifier "y")
                       , EIdentifier "z" ) ) ) )
       ]
;;

(* 23 *)
let%test _ =
  parse
    " let main = func (if x > 0 && y < 0 then x * y else 0) (let f t = t * t * t in (f \
     x) * (f x)) () "
  = Result.ok
    @@ [ EDeclaration
           ( "main"
           , []
           , EApplication
               ( EApplication
                   ( EApplication
                       ( EIdentifier "func"
                       , EIf
                           ( EBinaryOperation
                               ( AND
                               , EBinaryOperation (GT, EIdentifier "x", ELiteral (LInt 0))
                               , EBinaryOperation (LT, EIdentifier "y", ELiteral (LInt 0))
                               )
                           , EBinaryOperation (Mul, EIdentifier "x", EIdentifier "y")
                           , ELiteral (LInt 0) ) )
                   , ELetIn
                       ( [ EDeclaration
                             ( "f"
                             , [ "t" ]
                             , EBinaryOperation
                                 ( Mul
                                 , EBinaryOperation (Mul, EIdentifier "t", EIdentifier "t")
                                 , EIdentifier "t" ) )
                         ]
                       , EBinaryOperation
                           ( Mul
                           , EApplication (EIdentifier "f", EIdentifier "x")
                           , EApplication (EIdentifier "f", EIdentifier "x") ) ) )
               , ELiteral LUnit ) )
       ]
;;

(* 24 *)
let%test _ =
  parse
    " let main = if x * y / (z * z) > 15 || (f t) <= 0 || (fun x -> x * x) r >= 100 then \
     x - y - z * r else -1 "
  = Result.ok
    @@ [ EDeclaration
           ( "main"
           , []
           , EIf
               ( EBinaryOperation
                   ( OR
                   , EBinaryOperation
                       ( OR
                       , EBinaryOperation
                           ( GT
                           , EBinaryOperation
                               ( Div
                               , EBinaryOperation (Mul, EIdentifier "x", EIdentifier "y")
                               , EBinaryOperation (Mul, EIdentifier "z", EIdentifier "z")
                               )
                           , ELiteral (LInt 15) )
                       , EBinaryOperation
                           ( LTE
                           , EApplication (EIdentifier "f", EIdentifier "t")
                           , ELiteral (LInt 0) ) )
                   , EBinaryOperation
                       ( GTE
                       , EApplication
                           ( EFun
                               ( [ "x" ]
                               , EBinaryOperation (Mul, EIdentifier "x", EIdentifier "x")
                               )
                           , EIdentifier "r" )
                       , ELiteral (LInt 100) ) )
               , EBinaryOperation
                   ( Sub
                   , EBinaryOperation (Sub, EIdentifier "x", EIdentifier "y")
                   , EBinaryOperation (Mul, EIdentifier "z", EIdentifier "r") )
               , EUnaryOperation (Minus, ELiteral (LInt 1)) ) )
       ]
;;

(* 25 *)
let%test _ =
  parse " let main = if not(x = 5) && y = 5 then f x else f y "
  = Result.ok
    @@ [ EDeclaration
           ( "main"
           , []
           , EIf
               ( EBinaryOperation
                   ( AND
                   , EUnaryOperation
                       (Not, EBinaryOperation (Eq, EIdentifier "x", ELiteral (LInt 5)))
                   , EBinaryOperation (Eq, EIdentifier "y", ELiteral (LInt 5)) )
               , EApplication (EIdentifier "f", EIdentifier "x")
               , EApplication (EIdentifier "f", EIdentifier "y") ) )
       ]
;;

(* 26 *)
let%test _ =
  parse " let main = match res with \n  | Some x -> x\n  | None -> 0 "
  = Result.ok
    @@ [ EDeclaration
           ( "main"
           , []
           , EMatchWith
               ( EIdentifier "res"
               , [ EDataConstructor ("Some", [ EIdentifier "x" ]), EIdentifier "x"
                 ; EDataConstructor ("None", []), ELiteral (LInt 0)
                 ] ) )
       ]
;;

(* 27 *)
let%test _ =
  parse " let main = match f x y with \n  | Ok _ -> 1\n  | _ -> 0 "
  = Result.ok
    @@ [ EDeclaration
           ( "main"
           , []
           , EMatchWith
               ( EApplication
                   (EApplication (EIdentifier "f", EIdentifier "x"), EIdentifier "y")
               , [ EDataConstructor ("Ok", [ EIdentifier "_" ]), ELiteral (LInt 1)
                 ; EIdentifier "_", ELiteral (LInt 0)
                 ] ) )
       ]
;;

(* 28 *)
let%test _ =
  parse " let head = fun list -> match list with \n  | h :: _ -> Some h\n  | _ -> None "
  = Result.ok
    @@ [ EDeclaration
           ( "head"
           , []
           , EFun
               ( [ "list" ]
               , EMatchWith
                   ( EIdentifier "list"
                   , [ ( EConstructList (EIdentifier "h", EIdentifier "_")
                       , EDataConstructor ("Some", [ EIdentifier "h" ]) )
                     ; EIdentifier "_", EDataConstructor ("None", [])
                     ] ) ) )
       ]
;;

(* 29 *)
let%test _ =
  parse " let tail = fun list -> match list with \n  | _ :: t -> Some t\n | _ -> None "
  = Result.ok
    @@ [ EDeclaration
           ( "tail"
           , []
           , EFun
               ( [ "list" ]
               , EMatchWith
                   ( EIdentifier "list"
                   , [ ( EConstructList (EIdentifier "_", EIdentifier "t")
                       , EDataConstructor ("Some", [ EIdentifier "t" ]) )
                     ; EIdentifier "_", EDataConstructor ("None", [])
                     ] ) ) )
       ]
;;

(* 30 *)
let%test _ =
  parse " let rec length list = match list with \n  | _ :: t -> 1 + length t\n | _ -> 0 "
  = Result.ok
    @@ [ ERecursiveDeclaration
           ( "length"
           , [ "list" ]
           , EMatchWith
               ( EIdentifier "list"
               , [ ( EConstructList (EIdentifier "_", EIdentifier "t")
                   , EBinaryOperation
                       ( Add
                       , ELiteral (LInt 1)
                       , EApplication (EIdentifier "length", EIdentifier "t") ) )
                 ; EIdentifier "_", ELiteral (LInt 0)
                 ] ) )
       ]
;;

(* 31 *)
let%test _ =
  parse
    " let phi n = let rec helper last1 last2 n = if n > 0 then helper last2 (last1 + \
     last2) (n - 1) else last2 in\n\
    \  helper 1 1 (n - 2) "
  = Result.ok
    @@ [ EDeclaration
           ( "phi"
           , [ "n" ]
           , ELetIn
               ( [ ERecursiveDeclaration
                     ( "helper"
                     , [ "last1"; "last2"; "n" ]
                     , EIf
                         ( EBinaryOperation (GT, EIdentifier "n", ELiteral (LInt 0))
                         , EApplication
                             ( EApplication
                                 ( EApplication (EIdentifier "helper", EIdentifier "last2")
                                 , EBinaryOperation
                                     (Add, EIdentifier "last1", EIdentifier "last2") )
                             , EBinaryOperation (Sub, EIdentifier "n", ELiteral (LInt 1))
                             )
                         , EIdentifier "last2" ) )
                 ]
               , EApplication
                   ( EApplication
                       ( EApplication (EIdentifier "helper", ELiteral (LInt 1))
                       , ELiteral (LInt 1) )
                   , EBinaryOperation (Sub, EIdentifier "n", ELiteral (LInt 2)) ) ) )
       ]
;;

(* 32 *)
let%test _ =
  parse " let main = let sq x = x * x in sq x + sq y + sq z "
  = Result.ok
    @@ [ EDeclaration
           ( "main"
           , []
           , ELetIn
               ( [ EDeclaration
                     ( "sq"
                     , [ "x" ]
                     , EBinaryOperation (Mul, EIdentifier "x", EIdentifier "x") )
                 ]
               , EBinaryOperation
                   ( Add
                   , EBinaryOperation
                       ( Add
                       , EApplication (EIdentifier "sq", EIdentifier "x")
                       , EApplication (EIdentifier "sq", EIdentifier "y") )
                   , EApplication (EIdentifier "sq", EIdentifier "z") ) ) )
       ]
;;

(* 33 *)
let%test _ =
  parse " let mult x y z = x * y * z \n  let main = mult 5 6 7 "
  = Result.ok
    @@ [ EDeclaration
           ( "mult"
           , [ "x"; "y"; "z" ]
           , EBinaryOperation
               ( Mul
               , EBinaryOperation (Mul, EIdentifier "x", EIdentifier "y")
               , EIdentifier "z" ) )
       ; EDeclaration
           ( "main"
           , []
           , EApplication
               ( EApplication
                   ( EApplication (EIdentifier "mult", ELiteral (LInt 5))
                   , ELiteral (LInt 6) )
               , ELiteral (LInt 7) ) )
       ]
;;

(* 34 *)
let%test _ =
  parse
    " let main = match x, y, z with\n | Error x, Error y, Error z -> 0\n | _, _, _ -> 1 "
  = Result.ok
    @@ [ EDeclaration
           ( "main"
           , []
           , EMatchWith
               ( ETuple [ EIdentifier "x"; EIdentifier "y"; EIdentifier "z" ]
               , [ ( ETuple
                       [ EDataConstructor ("Error", [ EIdentifier "x" ])
                       ; EDataConstructor ("Error", [ EIdentifier "y" ])
                       ; EDataConstructor ("Error", [ EIdentifier "z" ])
                       ]
                   , ELiteral (LInt 0) )
                 ; ( ETuple [ EIdentifier "_"; EIdentifier "_"; EIdentifier "_" ]
                   , ELiteral (LInt 1) )
                 ] ) )
       ]
;;

(* 35 *)
let%test _ =
  parse
    " let f x y z = match x, y, z with\n\
    \  | true, true, false -> true\n\
    \  | true, false, true -> true\n\
    \  | false, true, true -> true\n\
    \  | _ -> false"
  = Result.ok
    @@ [ EDeclaration
           ( "f"
           , [ "x"; "y"; "z" ]
           , EMatchWith
               ( ETuple [ EIdentifier "x"; EIdentifier "y"; EIdentifier "z" ]
               , [ ( ETuple
                       [ ELiteral (LBool true)
                       ; ELiteral (LBool true)
                       ; ELiteral (LBool false)
                       ]
                   , ELiteral (LBool true) )
                 ; ( ETuple
                       [ ELiteral (LBool true)
                       ; ELiteral (LBool false)
                       ; ELiteral (LBool true)
                       ]
                   , ELiteral (LBool true) )
                 ; ( ETuple
                       [ ELiteral (LBool false)
                       ; ELiteral (LBool true)
                       ; ELiteral (LBool true)
                       ]
                   , ELiteral (LBool true) )
                 ; EIdentifier "_", ELiteral (LBool false)
                 ] ) )
       ]
;;
