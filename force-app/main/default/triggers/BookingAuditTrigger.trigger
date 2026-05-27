trigger BookingAuditTrigger on Booking__c (
    after insert,
    after update,
    after delete,
    after undelete
) {
    List<Booking__c> newEnriched = new List<Booking__c>();
    List<Booking__c> oldEnriched = new List<Booking__c>();

    if (Trigger.operationType == System.TriggerOperation.AFTER_DELETE ||
        Trigger.operationType == System.TriggerOperation.AFTER_UNDELETE) {
        // Deleted records cannot be re-queried — use Trigger.old directly.
        // Room name is resolved via fallback SOQL in BookingAuditHandler.resolveRoomName()
        if (Trigger.old != null) oldEnriched.addAll(Trigger.old);

    } else {
        // For insert/update — re-query to get Room_Name__r.Name populated
        Set<Id> ids = new Set<Id>();
        if (Trigger.new != null) for (Booking__c b : Trigger.new) ids.add(b.Id);
        if (Trigger.old != null) for (Booking__c b : Trigger.old) ids.add(b.Id);
        ids.remove(null);

        Map<Id, Booking__c> enriched = new Map<Id, Booking__c>();
        if (!ids.isEmpty()) {
            for (Booking__c b : [
                SELECT Id, Name, Room_Name__c, Room_Name__r.Name,
                       Employee_Name__c, Start_Time__c, End_Time__c, Status__c
                FROM Booking__c WHERE Id IN :ids
            ]) {
                enriched.put(b.Id, b);
            }
        }

        if (Trigger.new != null) {
            for (Booking__c b : Trigger.new) {
                newEnriched.add(enriched.containsKey(b.Id) ? enriched.get(b.Id) : b);
            }
        }
        if (Trigger.old != null) {
            for (Booking__c b : Trigger.old) {
                oldEnriched.add(enriched.containsKey(b.Id) ? enriched.get(b.Id) : b);
            }
        }
    }

    BookingAuditHandler.handle(
        newEnriched.isEmpty() ? null : newEnriched,
        oldEnriched.isEmpty() ? null : oldEnriched,
        Trigger.newMap,
        Trigger.oldMap,
        Trigger.operationType
    );
}
