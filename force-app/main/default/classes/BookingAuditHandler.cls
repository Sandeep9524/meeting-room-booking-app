public with sharing class BookingAuditHandler {

    private static final Integer IST_OFFSET_SECONDS = 19800; // UTC+5:30 for date filter

    // ── Entry point called from trigger ──────────────────────────────────────
    public static void handle(
        List<Booking__c>          newList,
        List<Booking__c>          oldList,
        Map<Id, Booking__c>       newMap,
        Map<Id, Booking__c>       oldMap,
        System.TriggerOperation   op
    ) {
        List<Booking_Audit__c> logs = new List<Booking_Audit__c>();

        if (op == System.TriggerOperation.AFTER_INSERT) {
            for (Booking__c b : newList) {
                logs.add(buildLog(b, null, 'Created'));
            }
        }
        else if (op == System.TriggerOperation.AFTER_UPDATE) {
            for (Booking__c b : newList) {
                Booking__c old = oldMap.get(b.Id);
                List<String> changed = getChangedFields(b, old);
                if (!changed.isEmpty()) {
                    Booking_Audit__c log = buildLog(b, old, 'Updated');
                    log.Changed_Fields__c = String.join(changed, ', ');
                    logs.add(log);
                }
            }
        }
        else if (op == System.TriggerOperation.AFTER_DELETE) {
            for (Booking__c b : oldList) {
                logs.add(buildLog(null, b, 'Deleted'));
            }
        }
        else if (op == System.TriggerOperation.AFTER_UNDELETE) {
            for (Booking__c b : newList) {
                logs.add(buildLog(b, null, 'Restored'));
            }
        }

        if (!logs.isEmpty()) {
            insert logs;
        }
    }

    // ── Safely read room name from relationship field ─────────────────────────
    private static String resolveRoomName(Booking__c b) {
        if (b.Room_Name__r != null && String.isNotBlank(b.Room_Name__r.Name)) {
            return b.Room_Name__r.Name;
        }
        if (b.Room_Name__c != null) {
            List<Meeting_Room__c> rooms = [SELECT Name FROM Meeting_Room__c WHERE Id = :b.Room_Name__c LIMIT 1];
            return rooms.isEmpty() ? '' : rooms[0].Name;
        }
        return '';
    }

    // ── Build a single audit record ───────────────────────────────────────────
    private static Booking_Audit__c buildLog(
        Booking__c newRec,
        Booking__c oldRec,
        String     action
    ) {
        Booking__c src = newRec != null ? newRec : oldRec;

        Booking_Audit__c log = new Booking_Audit__c(
            Action__c          = action,
            Timestamp__c       = DateTime.now(),
            Changed_By__c      = UserInfo.getName(),
            Changed_By_Id__c   = UserInfo.getUserId(),
            Room_Name__c       = resolveRoomName(src),
            Employee_Name__c   = src.Employee_Name__c
        );

        // Link to booking (only for non-delete — deleted records throw ENTITY_IS_DELETED)
        if (src.Id != null && action != 'Deleted') {
            log.Booking__c = src.Id;
        }

        // Snapshot old values
        if (oldRec != null) {
            log.Old_Start_Time__c = oldRec.Start_Time__c;
            log.Old_End_Time__c   = oldRec.End_Time__c;
            log.Old_Status__c     = oldRec.Status__c;
        }

        // Snapshot new values
        if (newRec != null) {
            log.New_Start_Time__c = newRec.Start_Time__c;
            log.New_End_Time__c   = newRec.End_Time__c;
            log.New_Status__c     = newRec.Status__c;
        }

        // Human-readable IST time in Changed_Fields__c
        TimeZone tz = UserInfo.getTimeZone();
        if (action == 'Created') {
            String startStr = newRec != null && newRec.Start_Time__c != null
                ? newRec.Start_Time__c.format('dd-MM-yyyy hh:mm a', tz.getID()) : '';
            String endStr   = newRec != null && newRec.End_Time__c != null
                ? newRec.End_Time__c.format('hh:mm a', tz.getID()) : '';
            log.Changed_Fields__c = startStr + ' \u2192 ' + endStr;
        } else if (action == 'Deleted') {
            String startStr = oldRec != null && oldRec.Start_Time__c != null
                ? oldRec.Start_Time__c.format('dd-MM-yyyy hh:mm a', tz.getID()) : '';
            String endStr   = oldRec != null && oldRec.End_Time__c != null
                ? oldRec.End_Time__c.format('hh:mm a', tz.getID()) : '';
            log.Changed_Fields__c = 'Canceled: ' + startStr + ' \u2192 ' + endStr;
        }

        return log;
    }

    // ── Detect which fields changed ───────────────────────────────────────────
    private static List<String> getChangedFields(Booking__c n, Booking__c o) {
        List<String> changed = new List<String>();
        if (n.Start_Time__c    != o.Start_Time__c)    changed.add('Start Time');
        if (n.End_Time__c      != o.End_Time__c)      changed.add('End Time');
        if (n.Status__c        != o.Status__c)        changed.add('Status');
        if (n.Room_Name__c     != o.Room_Name__c)     changed.add('Room');
        if (n.Employee_Name__c != o.Employee_Name__c) changed.add('Employee');
        return changed;
    }

    // ── LWC: fetch audit logs for a specific booking ──────────────────────────
    @AuraEnabled(cacheable=false)
    public static List<Booking_Audit__c> getAuditLogsForBooking(String bookingId) {
        return [
            SELECT Id, Action__c, Timestamp__c, Changed_By__c,
                   Old_Start_Time__c, New_Start_Time__c,
                   Old_End_Time__c,   New_End_Time__c,
                   Old_Status__c,     New_Status__c,
                   Changed_Fields__c, Room_Name__c, Employee_Name__c
            FROM Booking_Audit__c
            WHERE Booking__c = :bookingId
            ORDER BY Timestamp__c DESC
            LIMIT 100
        ];
    }

    // ── LWC: fetch all audit logs ─────────────────────────────────────────────
    @AuraEnabled(cacheable=false)
    public static List<AuditWrapper> getAllAuditLogs(
        Integer pageSize,
        Integer pageOffset,
        String  filterAction,
        String  filterUser,
        String  filterDate
    ) {
        String query =
            'SELECT Id, Action__c, Timestamp__c, Changed_By__c, ' +
            '       Booking__r.Name, Room_Name__c, Employee_Name__c, ' +
            '       Old_Start_Time__c, New_Start_Time__c, ' +
            '       Old_End_Time__c,   New_End_Time__c, ' +
            '       Old_Status__c,     New_Status__c, Changed_Fields__c ' +
            'FROM Booking_Audit__c ' +
            'WHERE Id != null ';

        if (String.isNotBlank(filterAction) && filterAction != 'All') {
            query += 'AND Action__c = \'' + String.escapeSingleQuotes(filterAction) + '\' ';
        }
        if (String.isNotBlank(filterUser)) {
            query += 'AND Changed_By__c LIKE \'%' + String.escapeSingleQuotes(filterUser) + '%\' ';
        }
        if (String.isNotBlank(filterDate)) {
            List<String> dp = filterDate.split('-');
            DateTime istMidnight = DateTime.newInstanceGmt(
                Integer.valueOf(dp[0]), Integer.valueOf(dp[1]), Integer.valueOf(dp[2]), 0, 0, 0);
            DateTime utcStart = istMidnight.addSeconds(-IST_OFFSET_SECONDS);
            DateTime utcEnd   = utcStart.addDays(1);
            query += 'AND Timestamp__c >= ' + toSoqlDatetime(utcStart) + ' ' +
                     'AND Timestamp__c <  ' + toSoqlDatetime(utcEnd) + ' ';
        }

        query += 'ORDER BY Timestamp__c DESC ' +
                 'LIMIT '  + pageSize   + ' ' +
                 'OFFSET ' + pageOffset;

        List<Booking_Audit__c> rows = Database.query(query);
        List<AuditWrapper> out = new List<AuditWrapper>();
        for (Booking_Audit__c r : rows) {
            out.add(new AuditWrapper(r));
        }
        return out;
    }

    // ── Total count for pagination ────────────────────────────────────────────
    @AuraEnabled(cacheable=false)
    public static Integer getAuditLogCount(
        String filterAction,
        String filterUser,
        String filterDate
    ) {
        String query = 'SELECT COUNT() FROM Booking_Audit__c WHERE Id != null ';
        if (String.isNotBlank(filterAction) && filterAction != 'All') {
            query += 'AND Action__c = \'' + String.escapeSingleQuotes(filterAction) + '\' ';
        }
        if (String.isNotBlank(filterUser)) {
            query += 'AND Changed_By__c LIKE \'%' + String.escapeSingleQuotes(filterUser) + '%\' ';
        }
        if (String.isNotBlank(filterDate)) {
            List<String> dp = filterDate.split('-');
            DateTime istMidnight = DateTime.newInstanceGmt(
                Integer.valueOf(dp[0]), Integer.valueOf(dp[1]), Integer.valueOf(dp[2]), 0, 0, 0);
            DateTime utcStart = istMidnight.addSeconds(-IST_OFFSET_SECONDS);
            DateTime utcEnd   = utcStart.addDays(1);
            query += 'AND Timestamp__c >= ' + toSoqlDatetime(utcStart) + ' ' +
                     'AND Timestamp__c <  ' + toSoqlDatetime(utcEnd) + ' ';
        }
        return Database.countQuery(query);
    }

    // ── Format DateTime as SOQL-safe UTC string e.g. 2026-05-28T04:00:00Z ─────
    private static String toSoqlDatetime(DateTime dt) {
        return dt.year()   + '-' +
               String.valueOf(dt.month()).leftPad(2,'0')  + '-' +
               String.valueOf(dt.day()).leftPad(2,'0')    + 'T' +
               String.valueOf(dt.hourGmt()).leftPad(2,'0')   + ':' +
               String.valueOf(dt.minuteGmt()).leftPad(2,'0') + ':' +
               String.valueOf(dt.secondGmt()).leftPad(2,'0') + 'Z';
    }

    // ── Wrapper for LWC serialization ─────────────────────────────────────────
    public class AuditWrapper {
        @AuraEnabled public String Id;
        @AuraEnabled public String BookingName;
        @AuraEnabled public String Action;
        @AuraEnabled public String ChangedBy;
        @AuraEnabled public String RoomName;
        @AuraEnabled public String EmployeeName;
        @AuraEnabled public String ChangedFields;
        @AuraEnabled public String OldStatus;
        @AuraEnabled public String NewStatus;
        @AuraEnabled public String OldStartTime;
        @AuraEnabled public String NewStartTime;
        @AuraEnabled public String OldEndTime;
        @AuraEnabled public String NewEndTime;
        @AuraEnabled public String TimestampDisplay;
        @AuraEnabled public Long   TimestampMs;

        public AuditWrapper(Booking_Audit__c r) {
            TimeZone tz = UserInfo.getTimeZone();
            this.Id               = r.Id;
            this.BookingName      = r.Booking__r != null ? r.Booking__r.Name : '—';
            this.Action           = r.Action__c;
            this.ChangedBy        = r.Changed_By__c;
            this.RoomName         = r.Room_Name__c;
            this.EmployeeName     = r.Employee_Name__c;
            this.ChangedFields    = r.Changed_Fields__c;
            this.OldStatus        = r.Old_Status__c;
            this.NewStatus        = r.New_Status__c;
            this.TimestampDisplay = r.Timestamp__c.format('dd-MM-yyyy HH:mm:ss', tz.getID());
            this.TimestampMs      = r.Timestamp__c.getTime();
            if (r.Old_Start_Time__c != null)
                this.OldStartTime = r.Old_Start_Time__c.format('dd-MM-yyyy HH:mm', tz.getID());
            if (r.New_Start_Time__c != null)
                this.NewStartTime = r.New_Start_Time__c.format('dd-MM-yyyy HH:mm', tz.getID());
            if (r.Old_End_Time__c   != null)
                this.OldEndTime   = r.Old_End_Time__c.format('dd-MM-yyyy HH:mm', tz.getID());
            if (r.New_End_Time__c   != null)
                this.NewEndTime   = r.New_End_Time__c.format('dd-MM-yyyy HH:mm', tz.getID());
        }
    }
}