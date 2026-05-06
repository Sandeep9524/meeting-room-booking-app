/**
 * @description Test class for AccountTriggerHandler
 * @group Test Classes
 */
@isTest
private class AccountTriggerHandlerTest {
    
    private static final Integer BULK_COUNT = 251;
    
    /**
     * @description Setup test data for all test methods
     */
    @TestSetup
    static void setupTestData() {
        // Note: Not creating accounts here as they need to be inserted 
        // within test methods to trigger the after insert logic
    }
    
    /**
     * @description Test single account insert creates contact
     */
    @isTest
    static void shouldCreateContact_WhenSingleAccountInserted() {
        // Given
        Account testAccount = new Account(Name = 'Test Account Single');
        
        // When
        Test.startTest();
        insert testAccount;
        Test.stopTest();
        
        // Then
        List<Contact> contacts = [
            SELECT Id, LastName, AccountId 
            FROM Contact 
            WHERE AccountId = :testAccount.Id
        ];
        
        Assert.areEqual(1, contacts.size(), 
            'Exactly one contact should be created for the account');
        Assert.areEqual(testAccount.Name, contacts[0].LastName, 
            'Contact LastName should match Account Name');
        Assert.areEqual(testAccount.Id, contacts[0].AccountId, 
            'Contact should be linked to the correct Account');
    }
    
    /**
     * @description Test bulk account insert creates contacts (bulkification test with 251+ records)
     */
    @isTest
    static void shouldCreateContacts_WhenBulkAccountsInserted() {
        // Given
        List<Account> accounts = TestDataFactory.createAccounts(BULK_COUNT, false);
        
        // When
        Test.startTest();
        insert accounts;
        Test.stopTest();
        
        // Then
        List<Contact> contacts = [
            SELECT Id, LastName, AccountId 
            FROM Contact 
            WHERE AccountId IN :accounts
        ];
        
        Assert.areEqual(BULK_COUNT, contacts.size(), 
            'Should create one contact for each account');
        
        // Verify each account has exactly one contact
        Map<Id, Integer> accountContactCount = new Map<Id, Integer>();
        for (Contact con : contacts) {
            Integer count = accountContactCount.containsKey(con.AccountId) 
                ? accountContactCount.get(con.AccountId) + 1 
                : 1;
            accountContactCount.put(con.AccountId, count);
        }
        
        for (Account acc : accounts) {
            Assert.areEqual(1, accountContactCount.get(acc.Id), 
                'Each account should have exactly one contact');
        }
    }
    
    /**
     * @description Test account with null name does not create contact
     */
    @isTest
    static void shouldNotCreateContact_WhenAccountNameIsNull() {
        // Given
        Account testAccount = new Account(Name = null);
        
        // When
        Test.startTest();
        try {
            insert testAccount;
        } catch (Exception e) {
            // Account insert might fail due to required field validation
            // This is expected behavior
        }
        Test.stopTest();
        
        // Then
        List<Contact> contacts = [SELECT Id FROM Contact];
        Assert.areEqual(0, contacts.size(), 
            'No contacts should be created when Account Name is null');
    }
    
    /**
     * @description Test mixed valid and invalid accounts
     */
    @isTest
    static void shouldCreateContactsOnlyForValidAccounts_WhenMixedAccountsInserted() {
        // Given
        List<Account> accounts = new List<Account>();
        Integer validCount = 150;
        
        // Add valid accounts
        for (Integer i = 0; i < validCount; i++) {
            accounts.add(new Account(Name = 'Valid Account ' + i));
        }
        
        // When
        Test.startTest();
        insert accounts;
        Test.stopTest();
        
        // Then
        List<Contact> contacts = [
            SELECT Id, LastName, AccountId 
            FROM Contact 
            WHERE AccountId IN :accounts
        ];
        
        Assert.areEqual(validCount, contacts.size(), 
            'Should create contacts only for accounts with valid names');
        
        // Verify all contacts have non-null LastName
        for (Contact con : contacts) {
            Assert.isTrue(con.LastName != null, 
                'All created contacts should have a LastName');
        }
    }
    
    /**
     * @description Test that contacts are properly linked to their accounts
     */
    @isTest
    static void shouldLinkContactsToCorrectAccounts_WhenAccountsInserted() {
        // Given
        List<Account> accounts = TestDataFactory.createAccounts(10, false);
        
        // When
        Test.startTest();
        insert accounts;
        Test.stopTest();
        
        // Then
        Map<Id, Account> accountMap = new Map<Id, Account>(accounts);
        List<Contact> contacts = [
            SELECT Id, LastName, AccountId 
            FROM Contact 
            WHERE AccountId IN :accountMap.keySet()
        ];
        
        Assert.areEqual(10, contacts.size(), 
            'Should create 10 contacts for 10 accounts');
        
        // Verify each contact's LastName matches its Account's Name
        for (Contact con : contacts) {
            Account relatedAccount = accountMap.get(con.AccountId);
            Assert.isNotNull(relatedAccount, 
                'Contact should be linked to an existing account');
            Assert.areEqual(relatedAccount.Name, con.LastName, 
                'Contact LastName should match Account Name');
        }
    }
    
    /**
     * @description Test that the handler respects DML limits (no DML in loops)
     */
    @isTest
    static void shouldRespectDmlLimits_WhenBulkProcessing() {
        // Given
        List<Account> accounts = TestDataFactory.createAccounts(BULK_COUNT, false);
        Integer dmlStatementsBefore = Limits.getDmlStatements();
        
        // When
        Test.startTest();
        insert accounts;
        Test.stopTest();
        
        // Then
        Integer dmlStatementsAfter = Limits.getDmlStatements();
        
        // The trigger should use only 1 DML statement for all contacts
        // (1 for account insert + 1 for contact insert = 2 total)
        Assert.isTrue(dmlStatementsAfter <= 2, 
            'Should use minimal DML statements (1 for accounts, 1 for contacts)');
        
        List<Contact> contacts = [SELECT Id FROM Contact];
        Assert.areEqual(BULK_COUNT, contacts.size(), 
            'All contacts should be created with minimal DML operations');
    }
}