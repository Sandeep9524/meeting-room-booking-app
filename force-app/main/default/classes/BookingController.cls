public with sharing class BookingController {

    /**
     * Accepts either:
     *   "YYYY-MM-DD HH:mm:ss"  — plain local string, parsed as ORG timezone by DateTime.valueOf()
     *   ISO-8601 with Z/offset — parsed as UTC/offset-aware
     */
    private static DateTime parseDateTime(String s) {
        if (String.isBlank(s)) {
            throw new AuraHandledException('Empty datetime string');
        }
        try {
            // Plain local string e.g. "2026-05-20 10:00:00" — no Z, no +offset
            // DateTime.valueOf() treats this as the org's local timezone. Exactly what we want.
            if (!s.contains('Z') && !s.contains('+') &&
                !(s.contains('T') && s.length() > 19)) {
                return DateTime.valueOf(s);
            }
            // ISO-8601 with timezone info — deserialise as UTC-aware
            return (DateTime) JSON.deserialize('"' + s + '"', DateTime.class);
        } catch (Exception e) {
            throw new AuraHandledException('Invalid datetime: ' + s + ' (' + e.getMessage() + ')');
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<RoomOption> getRooms() {
        List<RoomOption> out = new List<RoomOption>();
        for (Meeting_Room__c r : [SELECT Id, Name FROM Meeting_Room__c ORDER BY Name ASC]) {
            out.add(new RoomOption(r.Id, r.Name));
        }
        return out;
    }

    @AuraEnabled
    public static List<BookingWrapper> getBookings() {
        DateTime todayStart = DateTime.newInstance(System.today(), Time.newInstance(0,0,0,0));
        List<Booking__c> rows = [
            SELECT Id, Name, Room_Name__c, Room_Name__r.Name,
                   Employee_Name__c, Start_Time__c, End_Time__c, Status__c
            FROM Booking__c
            WHERE Start_Time__c >= :todayStart
            ORDER BY Start_Time__c ASC
            LIMIT 200
        ];
        List<BookingWrapper> out = new List<BookingWrapper>();
        for (Booking__c b : rows) out.add(new BookingWrapper(b));
        return out;
    }

    @AuraEnabled
    public static Boolean checkAvailability(String roomId, String startTime, String endTime) {
        try {
            DateTime startDT = parseDateTime(startTime);
            DateTime endDT   = parseDateTime(endTime);
            List<Booking__c> conflicts = [
                SELECT Id FROM Booking__c
                WHERE Room_Name__c = :roomId
                  AND Status__c    = 'Booked'
                  AND Start_Time__c < :endDT
                  AND End_Time__c   > :startDT
                LIMIT 1
            ];
            return conflicts.isEmpty();
        } catch (Exception e) {
            throw new AuraHandledException('Error checking availability: ' + e.getMessage());
        }
    }

    @AuraEnabled
    public static Booking__c createBooking(
            String roomId, String employeeName, String startTime, String endTime) {
        try {
            DateTime startDT = parseDateTime(startTime);
            DateTime endDT   = parseDateTime(endTime);

            // Reject past bookings
            if (startDT < DateTime.now()) {
                throw new AuraHandledException('Cannot book a slot in the past.');
            }

            // Double-check for conflicts before insert
            List<Booking__c> conflicts = [
                SELECT Id FROM Booking__c
                WHERE Room_Name__c = :roomId
                  AND Status__c    = 'Booked'
                  AND Start_Time__c < :endDT
                  AND End_Time__c   > :startDT
                LIMIT 1
            ];
            if (!conflicts.isEmpty()) {
                throw new AuraHandledException(
                    'This room is already booked for the selected time. Please choose a different slot.');
            }

            Booking__c rec = new Booking__c(
                Room_Name__c     = roomId,
                Employee_Name__c = employeeName,
                Start_Time__c    = startDT,
                End_Time__c      = endDT,
                Status__c        = 'Booked'
            );
            insert rec;
            return rec;

        } catch (AuraHandledException e) {
            throw e;
        } catch (DmlException e) {
            throw new AuraHandledException('Database error: ' + e.getDmlMessage(0));
        } catch (Exception e) {
            throw new AuraHandledException('Unexpected error: ' + e.getMessage());
        }
    }

    // ── Wrapper classes ───────────────────────────────────────────────────────

    public class BookingWrapper {
        @AuraEnabled public String Id;
        @AuraEnabled public String Name;
        @AuraEnabled public String RoomId;
        @AuraEnabled public String RoomName;
        @AuraEnabled public String EmployeeName;
        @AuraEnabled public String Status;
        @AuraEnabled public String DisplayStart;
        @AuraEnabled public String DisplayEnd;
        @AuraEnabled public Long   StartTimeMs; // kept for reference but not used for date matching
        @AuraEnabled public Long   EndTimeMs;
        // Local datetime strings in YYYY-MM-DD HH:mm format — used by JS for calendar matching
        @AuraEnabled public String StartLocal;
        @AuraEnabled public String EndLocal;

        public BookingWrapper(Booking__c b) {
            this.Id           = b.Id;
            this.Name         = b.Name;
            this.RoomId       = b.Room_Name__c;
            this.RoomName     = b.Room_Name__r != null ? b.Room_Name__r.Name : '';
            this.EmployeeName = b.Employee_Name__c;
            this.Status       = b.Status__c;
            this.StartTimeMs  = b.Start_Time__c.getTime();
            this.EndTimeMs    = b.End_Time__c.getTime();
            TimeZone tz       = UserInfo.getTimeZone();
            this.StartLocal   = b.Start_Time__c.format('yyyy-MM-dd HH:mm', tz.getID());
            this.EndLocal     = b.End_Time__c.format(  'yyyy-MM-dd HH:mm', tz.getID());
            this.DisplayStart = b.Start_Time__c.format('dd-MM-yyyy hh:mm a', tz.getID());
            this.DisplayEnd   = b.End_Time__c.format(  'dd-MM-yyyy hh:mm a', tz.getID());
        }
    }

    public class RoomOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        public RoomOption(String v, String l) { this.value = v; this.label = l; }
    }
}