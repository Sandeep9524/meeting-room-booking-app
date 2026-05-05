public class AccountTriggerHandler {

    public static void handleAfterInsert(List<Account> newAccounts) {

        List<Contact> contactsToInsert = new List<Contact>();

        for(Account acc : newAccounts) {

            if(acc.Name != null && acc.Id != null) {

                contactsToInsert.add(
                    new Contact(
                        LastName = acc.Name,
                        AccountId = acc.Id
                    )
                );
            }
        }

        if(!contactsToInsert.isEmpty()) {
            insert contactsToInsert;
        }
    }
}