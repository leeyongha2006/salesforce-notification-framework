@IsTest
private class RuleTransition_Test {

    private static final String RULE = 'StageName = \'Closed Won\' OR Amount >= 1000';

    private static Opportunity opportunity(String stage, Decimal amount) {
        return new Opportunity(Name = 'Demo', StageName = stage, Amount = amount);
    }

    @IsTest
    static void notifiesWhenConditionBecomesTrue() {
        Opportunity oldRecord = opportunity('Prospecting', 500);
        Opportunity newRecord = opportunity('Prospecting', 1200);
        Assert.isTrue(RuleTransition.shouldNotify(RULE, oldRecord, newRecord));
    }

    @IsTest
    static void doesNotNotifyAgainWhenConditionWasAlreadyTrue() {
        // 이미 Closed Won 이라 조건이 참인 상태에서 금액만 바뀐 경우.
        // 필드 변경만 보면 Amount 가 조건 필드라 다시 알림이 나가던 문제.
        Opportunity oldRecord = opportunity('Closed Won', 500);
        Opportunity newRecord = opportunity('Closed Won', 2000);
        Assert.isFalse(RuleTransition.shouldNotify(RULE, oldRecord, newRecord));
    }

    @IsTest
    static void doesNotNotifyWhenConditionIsFalse() {
        Opportunity oldRecord = opportunity('Prospecting', 100);
        Opportunity newRecord = opportunity('Qualification', 200);
        Assert.isFalse(RuleTransition.shouldNotify(RULE, oldRecord, newRecord));
    }

    @IsTest
    static void notifiesOnCreateWhenConditionIsTrue() {
        Assert.isTrue(RuleTransition.shouldNotify(RULE, null, opportunity('Closed Won', 0)));
        Assert.isFalse(RuleTransition.shouldNotify(RULE, null, opportunity('Prospecting', 0)));
    }

    @IsTest
    static void treatsNullToValueAsTransition() {
        Opportunity oldRecord = new Opportunity(Name = 'Demo');
        Opportunity newRecord = new Opportunity(Name = 'Demo', NextStep = 'Call');
        Assert.isTrue(RuleTransition.shouldNotify('NextStep != null', oldRecord, newRecord));
    }

    @IsTest
    static void fallsBackToFieldChangeForUnsupportedSyntax() {
        String rule = 'StageName IN (\'Closed Won\', \'Closed Lost\')';
        Assert.isTrue(RuleTransition.shouldNotify(rule, opportunity('Prospecting', 1), opportunity('Closed Won', 1)));
        Assert.isFalse(RuleTransition.shouldNotify(rule, opportunity('Closed Won', 1), opportunity('Closed Won', 5)));
    }

    @IsTest
    static void ignoresMissingNewRecord() {
        Assert.isFalse(RuleTransition.shouldNotify(RULE, opportunity('Closed Won', 1), null));
    }
}
