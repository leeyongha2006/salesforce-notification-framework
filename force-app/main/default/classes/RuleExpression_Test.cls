@IsTest
private class RuleExpression_Test {

    private static Map<String, Object> values() {
        return new Map<String, Object>{
            'StageName' => 'Closed Won',
            'Amount' => 1500,
            'Name' => 'Acme Renewal',
            'IsPrivate' => false,
            'NextStep' => null
        };
    }

    @IsTest
    static void comparesStringsWithoutCase() {
        Assert.isTrue(RuleExpression.evaluate('StageName = \'closed won\'', values()));
        Assert.isFalse(RuleExpression.evaluate('StageName != \'Closed Won\'', values()));
    }

    @IsTest
    static void comparesNumbers() {
        Assert.isTrue(RuleExpression.evaluate('Amount >= 1500', values()));
        Assert.isTrue(RuleExpression.evaluate('Amount > 1000.5', values()));
        Assert.isFalse(RuleExpression.evaluate('Amount < 1000', values()));
        Assert.isTrue(RuleExpression.evaluate('Amount <> 10', values()));
    }

    @IsTest
    static void handlesAndOrNotAndParentheses() {
        Assert.isTrue(RuleExpression.evaluate('Amount > 2000 OR StageName = \'Closed Won\'', values()));
        Assert.isFalse(RuleExpression.evaluate('Amount > 2000 AND StageName = \'Closed Won\'', values()));
        Assert.isTrue(RuleExpression.evaluate('(Amount > 2000 OR Amount < 2000) AND NOT IsPrivate = true', values()));
        // AND 가 OR 보다 먼저 계산된다.
        Assert.isTrue(RuleExpression.evaluate('Amount > 2000 AND IsPrivate = true OR Name LIKE \'Acme%\'', values()));
    }

    @IsTest
    static void handlesNullAndLike() {
        Assert.isTrue(RuleExpression.evaluate('NextStep = null', values()));
        Assert.isFalse(RuleExpression.evaluate('NextStep != null', values()));
        Assert.isTrue(RuleExpression.evaluate('Name LIKE \'%renew%\'', values()));
        Assert.isFalse(RuleExpression.evaluate('Name LIKE \'Beta_\'', values()));
        // 값이 없는 필드는 != 만 참이다.
        Assert.isTrue(RuleExpression.evaluate('NextStep != \'Call\'', values()));
        Assert.isFalse(RuleExpression.evaluate('NextStep = \'Call\'', values()));
    }

    @IsTest
    static void rejectsUnsupportedSyntax() {
        List<String> unsupported = new List<String>{
            'Account.Name = \'Acme\'',
            'StageName IN (\'A\', \'B\')',
            '(Amount > 1',
            'Amount >',
            '',
            'Amount > 1 Amount'
        };
        for (String expression : unsupported) {
            try {
                RuleExpression.evaluate(expression, values());
                Assert.fail('Expected UnsupportedException for: ' + expression);
            } catch (RuleExpression.UnsupportedException e) {
                Assert.isNotNull(e.getMessage());
            }
        }
    }

    @IsTest
    static void collectsReferencedFields() {
        Set<String> fields = RuleExpression.referencedFields('(StageName = \'A\' OR Amount > 1) AND Name LIKE \'B%\'');
        Assert.areEqual(new Set<String>{ 'stagename', 'amount', 'name' }, fields);

        Set<String> withNot = RuleExpression.referencedFields('Amount > 1 AND NOT IsPrivate = true OR StageName NOT IN (\'A\')');
        Assert.areEqual(new Set<String>{ 'amount', 'isprivate', 'stagename' }, withNot);
    }
}
