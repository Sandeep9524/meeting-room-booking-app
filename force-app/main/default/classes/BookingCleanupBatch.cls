global class BookingCleanupBatch implements Database.Batchable<SObject> {

    global Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator('SELECT Id FROM Booking__c WHERE Status__c = \'Expired\'');
    }

    global void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<Booking__c> bookings = (List<Booking__c>) scope;
        for (Booking__c b : bookings) {
            b.Status__c = 'Archived';
        }
        update bookings;
    }

    global void finish(Database.BatchableContext bc) {
        // optional post‑processing
    }
}
