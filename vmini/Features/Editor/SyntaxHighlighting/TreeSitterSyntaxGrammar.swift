import Foundation
import SwiftTreeSitter
import TreeSitterBash
import TreeSitterJava
import TreeSitterJavaQueries
import TreeSitterJSON
import TreeSitterKotlin
import TreeSitterMarkdown
import TreeSitterMarkdownInline
import TreeSitterSSHConfig
import TreeSitterSQL
import TreeSitterSQLQueries
import TreeSitterYAML

struct TreeSitterSyntaxDefinition: Sendable {
    let name: String
    let language: Language
    let highlightsQuery: SwiftTreeSitter.Query
    let inlineLanguage: Language?
    let inlineRangesQuery: SwiftTreeSitter.Query?
    let inlineHighlightsQuery: SwiftTreeSitter.Query?

    init(name: String, language: Language, highlightsQuery: String,
         inlineLanguage: Language? = nil, inlineHighlightsQuery: String? = nil) {
        self.name = name
        self.language = language
        self.highlightsQuery = try! SwiftTreeSitter.Query(language: language, data: Data(highlightsQuery.utf8))
        self.inlineLanguage = inlineLanguage
        if let inlineLanguage, let inlineHighlightsQuery {
            self.inlineHighlightsQuery = try! SwiftTreeSitter.Query(language: inlineLanguage, data: Data(inlineHighlightsQuery.utf8))
            inlineRangesQuery = try! SwiftTreeSitter.Query(language: language, data: Data("(inline) @inline".utf8))
        } else {
            self.inlineHighlightsQuery = nil
            inlineRangesQuery = nil
        }
    }
}

enum TreeSitterSyntaxGrammar {
    static func name(for language: SyntaxLanguage) -> String? {
        switch language {
        case .plaintext: nil
        case .bash, .dotenv: "bash"
        case .sshconfig: "ssh_config"
        case .markdown: "markdown"
        case .json: "json"
        case .yaml: "yaml"
        case .kotlin: "kotlin"
        case .java: "java"
        case .sql: "sql"
        }
    }

    static func definition(for syntax: SyntaxLanguage) -> TreeSitterSyntaxDefinition? {
        switch syntax {
        case .plaintext: nil
        case .bash: bash
        case .dotenv: dotenv
        case .sshconfig: sshConfig
        case .markdown: markdown
        case .json: json
        case .yaml: yaml
        case .kotlin: kotlin
        case .java: java
        case .sql: sql
        }
    }

    // Query compilation is expensive; static lets initialize once per language, safely across workers.
    private static let bash = TreeSitterSyntaxDefinition(
        name: "bash", language: Language(language: tree_sitter_bash()), highlightsQuery: bashQuery)
    // shortcut: dotenv uses Bash grammar; switch when a dedicated dotenv grammar is available.
    private static let dotenv = TreeSitterSyntaxDefinition(
        name: "bash", language: Language(language: tree_sitter_bash()), highlightsQuery: dotenvQuery)
    private static let sshConfig = TreeSitterSyntaxDefinition(
        name: "ssh_config", language: Language(language: tree_sitter_ssh_config()), highlightsQuery: sshConfigQuery)
    private static let markdown = TreeSitterSyntaxDefinition(
        name: "markdown", language: Language(language: tree_sitter_markdown()), highlightsQuery: markdownBlockQuery,
        inlineLanguage: Language(language: tree_sitter_markdown_inline()), inlineHighlightsQuery: markdownInlineQuery)
    private static let json = TreeSitterSyntaxDefinition(
        name: "json", language: Language(language: tree_sitter_json()), highlightsQuery: jsonQuery)
    private static let yaml = TreeSitterSyntaxDefinition(
        name: "yaml", language: Language(language: tree_sitter_yaml()), highlightsQuery: yamlQuery)
    private static let kotlin = TreeSitterSyntaxDefinition(
        name: "kotlin", language: Language(language: tree_sitter_kotlin()), highlightsQuery: kotlinQuery)
    private static let java = TreeSitterSyntaxDefinition(
        name: "java", language: Language(language: tree_sitter_java()), highlightsQuery: javaQuery)
    private static let sql = TreeSitterSyntaxDefinition(
        name: "sql", language: Language(language: tree_sitter_sql()), highlightsQuery: sqlQuery)

    static func role(for capture: String, text: String, syntax: SyntaxLanguage) -> SyntaxColorRole? {
        switch capture {
        case "comment": return .comment
        case "string", "string.regexp", "string.escape", "character": return .string
        case "number", "float", "boolean": return .variable
        case "variable":
            if syntax == .java { return nil } // The upstream Java query applies this capture to every identifier.
            if syntax == .sql {
                if let first = text.first, "\"`[".contains(first) { return .propertyKey }
                return nil
            }
            return .variable
        case "variable.builtin", "parameter", "embedded": return .variable
        case "sqlParameter": return syntax == .sql ? .variable : nil
        case "sqlCastType": return syntax == .sql ? .builtin : nil
        case "javaContextualKeyword": return syntax == .java && javaKeywords.contains(text) ? .keyword : nil
        case "keyword", "keyword.function", "keyword.return", "include", "module":
            return syntax == .bash && text == "export" ? .builtin : .keyword
        case "builtin", "function", "function.call", "function.method", "function.builtin", "type", "type.builtin", "constant",
             "constant.builtin", "tag", "label", "namespace", "storageclass", "attribute":
            return syntax == .bash && text.hasPrefix("-") ? .option : .builtin
        case "option": return text.hasPrefix("-") ? .option : nil
        case "property", "propertyKey", "field": return .propertyKey
        case "operator", "punctuation.delimiter", "punctuation.bracket", "punctuation.special": return .operator
        case "headingMarker": return .headingMarker
        case "headingText": return .headingText
        case "listMarker": return .listMarker
        case "blockquoteMarker": return .blockquoteMarker
        case "thematicBreak": return .thematicBreak
        case "inlineCode": return .inlineCode
        case "emphasisMarker": return .emphasisMarker
        case "linkText": return .linkText
        case "linkURL": return .linkURL
        case "codeFence": return .codeFence
        default: return nil
        }
    }

    private static let bashQuery = #"""
    [(string) (raw_string) (heredoc_body) (heredoc_start)] @string
    (command_name) @function
    (function_definition name: (word) @function)
    [(simple_expansion) (expansion) (variable_name)] @variable
    ["case" "do" "done" "elif" "else" "esac" "export" "fi" "for" "function" "if" "in" "select" "then" "unset" "until" "while"] @keyword
    (comment) @comment
    (file_descriptor) @number
    [(command_substitution) (process_substitution) (expansion)] @embedded
    ["&&" ">" ">>" "<" "|" "||" "&" ";" "=" "(" ")" "{" "}" "[" "]"] @operator
    ((command (_) @option) (#match? @option "^--?"))
    """#

    private static let dotenvQuery = #"""
    (comment) @comment
    (variable_assignment name: (variable_name) @propertyKey)
    (variable_assignment value: (word) @string)
    (variable_assignment value: (string) @string)
    (variable_assignment value: (raw_string) @string)
    (expansion) @variable
    "export" @keyword
    "=" @operator
    """#

    private static let sshConfigQuery = #"""
    [(string) (pattern) (token) (uri)] @string
    [(number) (bytes) (time)] @number
    ["Host" "Match"] @keyword
    (parameter keyword: _ @keyword)
    (host_declaration argument: _ @builtin)
    (match_declaration (condition criteria: _ @variable))
    [(kex) (mac) (cipher) (key_sig) (authentication) (facility) (verbosity) (ipqos)] @builtin
    (variable) @variable
    (comment) @comment
    ["${" "}" "=" "!" "+" "-" "^" "*" "?" "," ":" "@"] @operator
    """#

    private static let jsonQuery = #"""
    (pair key: (_) @propertyKey)
    (string) @string
    (number) @number
    [(null) (true) (false)] @keyword
    ["{" "}" "[" "]" ":" ","] @operator
    """#

    private static let yamlQuery = #"""
    [(boolean_scalar) (null_scalar)] @keyword
    [(double_quote_scalar) (single_quote_scalar) (block_scalar) (string_scalar)] @string
    [(integer_scalar) (float_scalar)] @number
    (comment) @comment
    [(anchor_name) (alias_name)] @builtin
    (tag) @type
    [(yaml_directive) (tag_directive) (reserved_directive)] @attribute
    (block_mapping_pair key: (flow_node [(double_quote_scalar) (single_quote_scalar)] @property))
    (block_mapping_pair key: (flow_node (plain_scalar (string_scalar) @property)))
    (flow_mapping (_ key: (flow_node [(double_quote_scalar) (single_quote_scalar)] @property)))
    (flow_mapping (_ key: (flow_node (plain_scalar (string_scalar) @property))))
    ["," "-" ":" ">" "?"] @punctuation.delimiter
    ["[" "]" "{" "}"] @punctuation.bracket
    ["*" "&" "---" "..."] @punctuation.special
    """#

    private static let kotlinQuery = #"""
    (simple_identifier) @variable
    (type_identifier) @type
    [(line_comment) (multiline_comment)] @comment
    [(string_literal) (character_literal)] @string
    [(real_literal) (integer_literal) (long_literal) (hex_literal) (bin_literal) (unsigned_literal)] @number
    [(boolean_literal) "null"] @keyword
    [(class_modifier) (member_modifier) (function_modifier) (property_modifier) (platform_modifier)
     (variance_modifier) (parameter_modifier) (visibility_modifier) (reification_modifier) (inheritance_modifier)] @keyword
    ["val" "var" "enum" "class" "object" "interface" "fun" "if" "else" "when" "for" "do" "while"
     "try" "catch" "throw" "finally" "package" "import" "this" "super" "typealias"
     "constructor" "init" "by" "where" "get" "set"] @keyword
    (jump_expression) @keyword
    ["!" "!=" "!==" "=" "==" "===" ">" ">=" "<" "<=" "||" "&&" "+" "++" "+=" "-" "--" "-="
     "*" "*=" "/" "/=" "%" "%=" "?." "?:" "!!" "is" "!is" "in" "!in" "as" "as?" ".." "->"] @operator
    ["(" ")" "[" "]" "{" "}"] @punctuation.bracket
    ["." "," ";" ":" "::"] @punctuation.delimiter
    """#

    private static let markdownBlockQuery = #"""
    (atx_heading [(atx_h1_marker) (atx_h2_marker) (atx_h3_marker) (atx_h4_marker) (atx_h5_marker) (atx_h6_marker)] @headingMarker)
    (atx_heading (inline) @headingText)
    (setext_heading (paragraph) @headingText)
    [(setext_h1_underline) (setext_h2_underline)] @headingMarker
    [(list_marker_plus) (list_marker_minus) (list_marker_star) (list_marker_dot) (list_marker_parenthesis)] @listMarker
    (block_quote_marker) @blockquoteMarker
    (thematic_break) @thematicBreak
    (fenced_code_block_delimiter) @codeFence
    """#

    private static let markdownInlineQuery = #"""
    [(code_span) (link_title)] @inlineCode
    (emphasis_delimiter) @emphasisMarker
    [(link_text) (image_description)] @linkText
    [(link_destination) (uri_autolink)] @linkURL
    """#

    private static let sqlQuery = (try! String(contentsOf: TreeSitterSQLQueries.Query.highlightsFileURL, encoding: .utf8)) + #"""

    (ERROR) @sqlParameter
    ; shortcut: this grammar exposes CAST's target type as an alias child; replace if it adds a cast node.
    ((alias
      (function_call function: (identifier) @sqlCastFunction)
      (identifier) @sqlCastType)
     (#match? @sqlCastFunction "^[Cc][Aa][Ss][Tt]$"))
    ["IS"] @keyword
    """#

    private static let javaQuery = (try! String(contentsOf: TreeSitterJavaQueries.Query.highlightsFileURL, encoding: .utf8)) + #"""

    (text_block) @string
    (binary_integer_literal) @number
    (annotation name: (_) @builtin)
    (marker_annotation name: (_) @builtin)
    ["@interface"] @keyword
    ["permits" "record" "yield"] @keyword
    (identifier) @javaContextualKeyword
    ["=" "+" "-" "*" "/" "%" "!" "<" ">" "&" "|" "?" "^" "~" "." ":" ";" "(" ")"
     "{" "}" "[" "]" "," "@" "+=" "-=" "*=" "/=" "%=" "&=" "|=" "^=" "==" "!=" "<=" ">="
     "&&" "||" "++" "--" "<<" ">>" ">>>" "<<=" ">>=" ">>>=" "->" "::"] @operator
    """#

    private static let javaKeywords: Set<String> = [
        "module", "open", "requires", "transitive", "exports", "opens", "to", "uses", "provides", "with",
        "record", "sealed", "permits", "non-sealed", "var", "yield", "when"
    ]

}
