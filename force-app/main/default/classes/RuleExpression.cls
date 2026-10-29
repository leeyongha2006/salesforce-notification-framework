/**
 * 알림 조건식(SOQL WHERE 절의 일부 문법)을 메모리에서 계산한다.
 *
 * 지원: 비교(=, !=, <>, <, >, <=, >=), LIKE, NULL 비교, AND / OR / NOT, 괄호.
 * 지원하지 않는 문법(관계 필드, 함수, IN, 서브쿼리 등)은 UnsupportedException 을 던진다.
 * 호출하는 쪽은 이 예외를 받아 다른 판정 방식으로 넘어가면 된다.
 *
 * 예) RuleExpression.evaluate('StageName = \'Closed Won\' OR Amount >= 1000', fieldValues)
 */
public with sharing class RuleExpression {

    public class UnsupportedException extends Exception {}

    private static final Set<String> COMPARE_OPERATORS = new Set<String>{ '=', '!=', '<>', '<', '>', '<=', '>=' };
    private static final Set<String> FIELD_OPERATORS = new Set<String>{ 'LIKE', 'IN', 'NOT', 'INCLUDES', 'EXCLUDES' };
    private static final Set<String> KEYWORDS = new Set<String>{ 'AND', 'OR', 'NOT', '(', ')', ',' };
    private static final Pattern TOKEN_PATTERN = Pattern.compile(
        '\\s*(\'(?:\\\\.|[^\'\\\\])*\'|!=|<>|<=|>=|=|<|>|\\(|\\)|,|[A-Za-z0-9_.\\-]+)'
    );

    private final List<String> tokens;
    private final Map<String, Object> values;
    private Integer position = 0;

    private RuleExpression(String expression, Map<String, Object> fieldValues) {
        this.tokens = tokenize(expression);
        this.values = new Map<String, Object>();
        if (fieldValues != null) {
            for (String fieldName : fieldValues.keySet()) {
                this.values.put(fieldName.toLowerCase(), fieldValues.get(fieldName));
            }
        }
    }

    /**
     * 조건식을 필드 값으로 계산한다. 필드 이름은 대소문자를 구분하지 않는다.
     */
    public static Boolean evaluate(String expression, Map<String, Object> fieldValues) {
        if (String.isBlank(expression)) {
            throw new UnsupportedException('Expression is empty.');
        }
        RuleExpression parser = new RuleExpression(expression, fieldValues);
        Boolean result = parser.parseOr();
        if (parser.peek() != null) {
            throw new UnsupportedException('Unexpected token: ' + parser.peek());
        }
        return result;
    }

    /**
     * 조건식에 쓰인 필드 이름(소문자)을 모은다. evaluate 가 지원하지 않는 IN 같은
     * 연산자도 필드는 찾아 주므로, 계산이 안 될 때 "필드가 바뀌었는가" 판단에 쓴다.
     */
    public static Set<String> referencedFields(String expression) {
        Set<String> fields = new Set<String>();
        List<String> tokenList = tokenize(expression);
        for (Integer i = 0; i < tokenList.size() - 1; i++) {
            String current = tokenList[i].toUpperCase();
            String next = tokenList[i + 1].toUpperCase();
            if (KEYWORDS.contains(current)) {
                continue;
            }
            if (COMPARE_OPERATORS.contains(next) || FIELD_OPERATORS.contains(next)) {
                fields.add(tokenList[i].toLowerCase());
            }
        }
        return fields;
    }

    private static List<String> tokenize(String expression) {
        List<String> result = new List<String>();
        if (expression == null) {
            return result;
        }
        Matcher matcher = TOKEN_PATTERN.matcher(expression);
        Integer consumed = 0;
        while (matcher.find()) {
            if (matcher.start() != consumed) {
                throw new UnsupportedException('Unsupported character near position ' + consumed);
            }
            result.add(matcher.group(1));
            consumed = matcher.end();
        }
        if (expression.substring(consumed).trim().length() > 0) {
            throw new UnsupportedException('Unsupported character near position ' + consumed);
        }
        return result;
    }

    private String peek() {
        return position < tokens.size() ? tokens[position] : null;
    }

    private String next() {
        String token = peek();
        if (token == null) {
            throw new UnsupportedException('Unexpected end of expression.');
        }
        position++;
        return token;
    }

    private Boolean isKeyword(String keyword) {
        String token = peek();
        return token != null && token.equalsIgnoreCase(keyword);
    }

    private Boolean parseOr() {
        Boolean result = parseAnd();
        while (isKeyword('OR')) {
            next();
            Boolean right = parseAnd();
            result = result || right;
        }
        return result;
    }

    private Boolean parseAnd() {
        Boolean result = parseNot();
        while (isKeyword('AND')) {
            next();
            Boolean right = parseNot();
            result = result && right;
        }
        return result;
    }

    private Boolean parseNot() {
        if (isKeyword('NOT')) {
            next();
            return !parseNot();
        }
        return parseGroupOrComparison();
    }

    private Boolean parseGroupOrComparison() {
        if (peek() == '(') {
            next();
            Boolean result = parseOr();
            if (next() != ')') {
                throw new UnsupportedException('Missing closing parenthesis.');
            }
            return result;
        }
        return parseComparison();
    }

    private Boolean parseComparison() {
        String fieldName = next();
        if (fieldName.contains('.')) {
            throw new UnsupportedException('Relationship fields are not supported: ' + fieldName);
        }
        String operator = next().toUpperCase();
        Object fieldValue = values.get(fieldName.toLowerCase());

        if (operator == 'LIKE') {
            String likePattern = unquote(next());
            String text = fieldValue == null ? '' : String.valueOf(fieldValue);
            return Pattern.matches('(?is)' + likeToRegex(likePattern), text);
        }
        if (!COMPARE_OPERATORS.contains(operator)) {
            throw new UnsupportedException('Unsupported operator: ' + operator);
        }
        return compare(fieldValue, toLiteral(next()), operator);
    }

    private static Object toLiteral(String token) {
        if (token.startsWith('\'')) {
            return unquote(token);
        }
        String lower = token.toLowerCase();
        if (lower == 'null') {
            return null;
        }
        if (lower == 'true' || lower == 'false') {
            return Boolean.valueOf(lower);
        }
        if (Pattern.matches('-?\\d+(\\.\\d+)?', token)) {
            return Decimal.valueOf(token);
        }
        throw new UnsupportedException('Unsupported literal: ' + token);
    }

    private static String unquote(String token) {
        if (token.length() >= 2 && token.startsWith('\'') && token.endsWith('\'')) {
            return token.substring(1, token.length() - 1).replace('\\\'', '\'');
        }
        return token;
    }

    private static String likeToRegex(String likePattern) {
        String regex = '';
        for (Integer i = 0; i < likePattern.length(); i++) {
            String ch = likePattern.substring(i, i + 1);
            if (ch == '%') {
                regex += '.*';
            } else if (ch == '_') {
                regex += '.';
            } else {
                regex += Pattern.quote(ch);
            }
        }
        return regex;
    }

    private static Boolean compare(Object fieldValue, Object literal, String operator) {
        Boolean isEqualOperator = operator == '=';
        Boolean isNotEqualOperator = operator == '!=' || operator == '<>';

        if (literal == null) {
            if (isEqualOperator) {
                return fieldValue == null;
            }
            if (isNotEqualOperator) {
                return fieldValue != null;
            }
            throw new UnsupportedException('NULL can only be compared with = or !=.');
        }
        if (fieldValue == null) {
            return isNotEqualOperator;
        }
        if (literal instanceof Decimal) {
            Decimal left = Decimal.valueOf(String.valueOf(fieldValue));
            Decimal right = (Decimal) literal;
            return compareNumbers(left, right, operator);
        }
        if (literal instanceof Boolean) {
            Boolean same = Boolean.valueOf(String.valueOf(fieldValue)) == (Boolean) literal;
            return compareEquality(same, operator);
        }
        // SOQL 문자열 비교처럼 대소문자를 구분하지 않는다.
        Boolean same = String.valueOf(fieldValue).equalsIgnoreCase((String) literal);
        return compareEquality(same, operator);
    }

    private static Boolean compareNumbers(Decimal left, Decimal right, String operator) {
        switch on operator {
            when '=' { return left == right; }
            when '!=', '<>' { return left != right; }
            when '<' { return left < right; }
            when '>' { return left > right; }
            when '<=' { return left <= right; }
            when else { return left >= right; }
        }
    }

    private static Boolean compareEquality(Boolean same, String operator) {
        if (operator == '=') {
            return same;
        }
        if (operator == '!=' || operator == '<>') {
            return !same;
        }
        throw new UnsupportedException('Operator ' + operator + ' needs a number.');
    }
}
