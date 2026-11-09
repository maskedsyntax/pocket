import Foundation

/// Evaluates arithmetic typed into the search field, like Spotlight's calculator.
///
/// Supports `+ - * / ^ %` (and `× ÷ − **`), parentheses (a missing closing
/// parenthesis at the end is filled in), implicit multiplication (`2pi`, `3(4+1)`),
/// factorial `!`, `mod`, `x` / `of` as multiplication (`3 x 4`, `20% of 150`),
/// thousands separators (`1,500`), scientific notation (`2e3`), the constants
/// `pi` / `π` / `e` / `tau`, and the functions listed in `functions` (trig in radians).
///
/// A trailing percentage on an addend is relative to the left side, the way pocket
/// calculators work: `200 + 10%` is 220.
enum Calculator {
    struct Result: Equatable {
        let expression: String
        let value: Double
        /// Localized, with grouping separators: "1,234.5".
        let display: String
        /// What gets copied: no grouping, "." as the decimal point.
        let plain: String
    }

    /// Returns nil unless `input` is a complete calculation: a lone number or
    /// constant ("42", "pi", "e") is not one, so typing app names stays quiet.
    static func evaluate(_ input: String) -> Result? {
        let expression = input.trimmingCharacters(in: .whitespaces)
        guard !expression.isEmpty, let tokens = tokenize(expression) else { return nil }

        var parser = Parser(tokens: tokens)
        guard var value = try? parser.parse(), parser.isCalculation, value.isFinite else {
            return nil
        }
        // Trig noise like sin(pi) = 1.2e-16 should read as 0, and never show "-0".
        if abs(value) < 1e-12 { value = 0 }
        return Result(
            expression: expression, value: value, display: format(value, grouped: true),
            plain: format(value, grouped: false))
    }

    // MARK: - Formatting

    private static func format(_ value: Double, grouped: Bool) -> String {
        let magnitude = abs(value)
        if magnitude >= 1e15 || (magnitude < 1e-6 && magnitude > 0) {
            return String(format: "%.10g", value)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesSignificantDigits = true
        formatter.maximumSignificantDigits = 15
        formatter.usesGroupingSeparator = grouped
        formatter.locale = grouped ? .current : Locale(identifier: "en_US_POSIX")
        return formatter.string(from: value as NSNumber) ?? String(value)
    }

    // MARK: - Tokens

    fileprivate enum Token: Equatable {
        case number(Double)
        case word(String)
        case op(Character)
    }

    fileprivate static let constants: [String: Double] = [
        "pi": .pi, "π": .pi, "e": M_E, "tau": 2 * .pi,
    ]

    fileprivate static let functions: [String: (Double) -> Double] = [
        "sqrt": { $0.squareRoot() }, "cbrt": cbrt, "abs": { Swift.abs($0) },
        "sin": sin, "cos": cos, "tan": tan, "asin": asin, "acos": acos, "atan": atan,
        "sinh": sinh, "cosh": cosh, "tanh": tanh,
        "ln": log, "log": log10, "log10": log10, "log2": log2, "exp": exp,
        "round": { $0.rounded() }, "floor": floor, "ceil": ceil,
    ]

    private static func tokenize(_ text: String) -> [Token]? {
        let chars = Array(text)
        var tokens: [Token] = []
        var i = 0

        func isDigit(_ index: Int) -> Bool { index < chars.count && chars[index].isASCII && chars[index].isNumber }

        while i < chars.count {
            let ch = chars[i]
            if ch.isWhitespace {
                i += 1
            } else if isDigit(i) || (ch == "." && isDigit(i + 1)) {
                var literal = ""
                while i < chars.count {
                    if isDigit(i) || chars[i] == "." {
                        literal.append(chars[i])
                        i += 1
                    } else if chars[i] == ",", (1...3).allSatisfy({ isDigit(i + $0) }), !isDigit(i + 4) {
                        i += 1  // thousands separator: "1,500"
                    } else if chars[i] == "e" || chars[i] == "E",
                        isDigit(i + 1) || ((chars[safe: i + 1] == "-" || chars[safe: i + 1] == "+") && isDigit(i + 2))
                    {
                        literal.append("e")
                        literal.append(chars[i + 1])
                        i += 2  // exponent: "2e3", "1.5e-4"
                    } else {
                        break
                    }
                }
                guard let value = Double(literal) else { return nil }
                tokens.append(.number(value))
            } else if ch.isLetter || ch == "π" {
                var word = ""
                // Digits only continue "log2" / "log10", so "3x4" reads as 3 × 4.
                while i < chars.count, chars[i].isLetter || chars[i] == "π" || (word.hasPrefix("log") && isDigit(i)) {
                    word.append(chars[i])
                    i += 1
                }
                tokens.append(.word(word.lowercased()))
            } else if ch == "*" && chars[safe: i + 1] == "*" {
                tokens.append(.op("^"))
                i += 2
            } else {
                switch ch {
                case "+", "-", "*", "/", "^", "%", "!", "(", ")": tokens.append(.op(ch))
                case "×", "·", "∙": tokens.append(.op("*"))
                case "÷": tokens.append(.op("/"))
                case "−", "–": tokens.append(.op("-"))
                default: return nil
                }
                i += 1
            }
        }
        return tokens
    }

    // MARK: - Parser

    /// Recursive descent, lowest precedence first:
    /// expression (+ -) → term (* / mod, implicit) → unary (-) → power (^, right-assoc) → postfix (% !) → primary.
    fileprivate struct Parser {
        struct Failure: Error {}

        let tokens: [Token]
        var pos = 0
        /// Set once an operator or function is used, so "42" alone isn't a calculation.
        var isCalculation = false
        /// Whether the last postfix chain ended in "%", for `a + b%`.
        private var endedInPercent = false

        init(tokens: [Token]) { self.tokens = tokens }

        mutating func parse() throws -> Double {
            let value = try expression()
            guard pos == tokens.count else { throw Failure() }
            return value
        }

        private var peek: Token? { pos < tokens.count ? tokens[pos] : nil }

        private mutating func expression() throws -> Double {
            var (value, _) = try term()
            while case .op(let op)? = peek, op == "+" || op == "-" {
                pos += 1
                isCalculation = true
                var (rhs, isPercent) = try term()
                if isPercent { rhs *= value }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        /// Returns the value and whether the term is a bare percentage ("10%").
        private mutating func term() throws -> (Double, Bool) {
            var value = try unary()
            var isPercent = endedInPercent
            while let token = peek {
                switch token {
                case .op("*"), .op("/"):
                    pos += 1
                    let rhs = try unary()
                    if token == .op("/") {
                        guard rhs != 0 else { throw Failure() }
                        value /= rhs
                    } else {
                        value *= rhs
                    }
                case .word("mod"):
                    pos += 1
                    let rhs = try unary()
                    guard rhs != 0 else { throw Failure() }
                    value = value.truncatingRemainder(dividingBy: rhs)
                case .word("x"), .word("of"):
                    pos += 1
                    value *= try unary()
                case .op("("), .word:
                    value *= try unary()  // implicit: "2pi", "3(4 + 1)"
                default:
                    return (value, isPercent)
                }
                isCalculation = true
                isPercent = false
            }
            return (value, isPercent)
        }

        private mutating func unary() throws -> Double {
            if case .op(let op)? = peek, op == "-" || op == "+" {
                pos += 1
                let value = try unary()
                return op == "-" ? -value : value
            }
            return try power()
        }

        private mutating func power() throws -> Double {
            let base = try postfix()
            guard peek == .op("^") else { return base }
            pos += 1
            isCalculation = true
            let exponent = try unary()
            endedInPercent = false
            return pow(base, exponent)
        }

        private mutating func postfix() throws -> Double {
            var value = try primary()
            endedInPercent = false
            while case .op(let op)? = peek, op == "%" || op == "!" {
                pos += 1
                isCalculation = true
                if op == "%" {
                    value /= 100
                    endedInPercent = true
                } else {
                    guard value >= 0, value <= 170, value == value.rounded() else { throw Failure() }
                    value = value == 0 ? 1 : (1...Int(value)).reduce(1.0) { $0 * Double($1) }
                    endedInPercent = false
                }
            }
            return value
        }

        private mutating func primary() throws -> Double {
            guard let token = peek else { throw Failure() }
            pos += 1
            switch token {
            case .number(let value):
                return value
            case .op("("):
                let value = try expression()
                if peek == .op(")") {
                    pos += 1
                } else if peek != nil {
                    throw Failure()
                }  // else: end of input, treat the parenthesis as closed
                return value
            case .word(let word):
                if let constant = Calculator.constants[word] { return constant }
                if let function = Calculator.functions[word] {
                    isCalculation = true
                    return function(try postfix())
                }
                throw Failure()
            default:
                throw Failure()
            }
        }
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
