/**
 * @description Factory class for creating test data
 * @group Test Utilities
 */
@isTest
public class TestDataFactory {
    
    /**
     * @description Creates Account records for testing
     * @param count Number of accounts to create
     * @param doInsert Whether to insert the records
     * @return List of Account records
     */
    public static List<Account> createAccounts(Integer count, Boolean doInsert) {
        List<Account> accounts = new List<Account>();
        
        for (Integer i = 0; i < count; i++) {
            accounts.add(new Account(
                Name = 'Test Account ' + i
            ));
        }
        
        if (doInsert) {
            insert accounts;
        }
        
        return accounts;
    }
    
    /**
     * @description Creates Account records with specific field values
     * @param count Number of accounts to create
     * @param fieldValues Map of field names to values to override
     * @param doInsert Whether to insert the records
     * @return List of Account records
     */
    public static List<Account> createAccounts(Integer count, Map<String, Object> fieldValues, Boolean doInsert) {
        List<Account> accounts = new List<Account>();
        
        for (Integer i = 0; i < count; i++) {
            Account acc = new Account(
                Name = 'Test Account ' + i
            );
            
            // Apply field overrides
            if (fieldValues != null) {
                for (String fieldName : fieldValues.keySet()) {
                    acc.put(fieldName, fieldValues.get(fieldName));
                }
            }
            
            accounts.add(acc);
        }
        
        if (doInsert) {
            insert accounts;
        }
        
        return accounts;
    }
}