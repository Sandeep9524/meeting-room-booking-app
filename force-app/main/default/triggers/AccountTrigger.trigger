trigger AccountTrigger on Account(after insert) {
    // Delegate to handler
    AccountTriggerHandler.handleAfterInsert(Trigger.new);
}
