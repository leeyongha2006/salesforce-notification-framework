/**
 * 레코드가 바뀌었을 때 알림을 보낼지 판단한다.
 *
 * "조건에 쓰인 필드가 바뀌었는가" 만 보면, OR 조건이 이미 참인 상태에서
 * 다른 조건 필드만 바뀌어도 알림이 다시 나간다 (중복 발송).
 * 그래서 수정 전 값으로 조건식을 다시 계산해, 거짓 → 참으로 바뀐 경우에만 보낸다.
 *
 * 조건식을 해석할 수 없으면(지원하지 않는 문법) 알림을 막지 않고
 * "조건 필드가 바뀌었는가" 로 판단한다.
 */
public with sharing class RuleTransition {

    /**
     * @param expression 알림 조건식
     * @param oldRecord  수정 전 레코드 (생성이면 null)
     * @param newRecord  수정 후 레코드
     * @return 알림을 보내야 하면 true
     */
    public static Boolean shouldNotify(String expression, SObject oldRecord, SObject newRecord) {
        if (newRecord == null) {
            return false;
        }
        Map<String, Object> newValues = newRecord.getPopulatedFieldsAsMap();
        try {
            if (!RuleExpression.evaluate(expression, newValues)) {
                return false;
            }
            if (oldRecord == null) {
                return true;
            }
            return !RuleExpression.evaluate(expression, oldRecord.getPopulatedFieldsAsMap());
        } catch (RuleExpression.UnsupportedException e) {
            return oldRecord == null || hasReferencedFieldChanged(expression, oldRecord, newRecord);
        }
    }

    private static Boolean hasReferencedFieldChanged(String expression, SObject oldRecord, SObject newRecord) {
        Set<String> fields;
        try {
            fields = RuleExpression.referencedFields(expression);
        } catch (RuleExpression.UnsupportedException e) {
            // 필드조차 알아낼 수 없으면 보내는 쪽으로 판단한다 (누락보다 중복이 낫다).
            return true;
        }
        Map<String, Object> oldValues = lowerCaseKeys(oldRecord.getPopulatedFieldsAsMap());
        Map<String, Object> newValues = lowerCaseKeys(newRecord.getPopulatedFieldsAsMap());
        for (String field : fields) {
            // null → 값 변경도 바뀐 것으로 본다.
            if (oldValues.get(field) != newValues.get(field)) {
                return true;
            }
        }
        return false;
    }

    private static Map<String, Object> lowerCaseKeys(Map<String, Object> source) {
        Map<String, Object> result = new Map<String, Object>();
        for (String key : source.keySet()) {
            result.put(key.toLowerCase(), source.get(key));
        }
        return result;
    }
}
