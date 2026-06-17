public with sharing class BookingApprovalService {

    // ── Submit booking for approval ───────────────────────────────────────────
    public static void submitForApproval(Id bookingId) {
        try {
            // Submit to approval process
            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(bookingId);
            req.setProcessDefinitionNameOrId('Board_Room_Approval');
            req.setSkipEntryCriteria(false);
            Approval.ProcessResult submitResult = Approval.process(req);
            System.debug('Approval submitted: ' + submitResult.isSuccess());

            if (submitResult.isSuccess()) {
                // Both auto-approve and email run in separate transaction via Queueable
                System.enqueueJob(new AutoApproveStep1Queueable(bookingId, UserInfo.getUserId()));
            }
        } catch (Exception e) {
            System.debug('Approval submit error: ' + e.getMessage());
        }
    }

    // ── Send approval request email to manager ───────────────────────────────
    public static void sendApprovalRequestEmailPublic(Id bookingId) {
        try {
            Booking__c b = [
                SELECT Id, Name, Room_Name__r.Name, Employee_Name__c,
                       Start_Time__c, End_Time__c, CreatedById
                FROM Booking__c WHERE Id = :bookingId LIMIT 1
            ];

            // Get manager of the booker
            User booker = [SELECT Id, Name, ManagerId FROM User WHERE Id = :b.CreatedById LIMIT 1];
            if (booker.ManagerId == null) {
                System.debug('No manager set for booker — skipping approval email');
                return;
            }
            User manager = [SELECT Id, Name, Email FROM User WHERE Id = :booker.ManagerId LIMIT 1];

            String tzId     = 'Asia/Kolkata'; // always use org timezone (IST) — not user's local tz
            String startStr = b.Start_Time__c.format('dd-MM-yyyy hh:mm a', tzId);
            String endStr   = b.End_Time__c.format('hh:mm a', tzId);
            String roomName = b.Room_Name__r != null ? b.Room_Name__r.Name : 'Board Room';

            String approveUrl = System.URL.getOrgDomainUrl().toExternalForm() +
                '/lightning/page/approval';

            String html =
                '<div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;">' +
                '<div style="background:#032d60;padding:20px 28px;border-radius:8px 8px 0 0;">' +
                '<h2 style="color:#fff;margin:0;">📋 Approval Required — Board Room</h2>' +
                '</div>' +
                '<div style="background:#fff;border:1px solid #e3e6ea;border-top:none;' +
                'padding:24px 28px;border-radius:0 0 8px 8px;">' +
                '<p style="font-size:14px;color:#444;margin-bottom:16px;">' +
                'Hi ' + manager.Name + ',<br><br>' +
                '<strong>' + b.Employee_Name__c + '</strong> has requested to book the ' +
                '<strong>' + roomName + '</strong> and requires your approval.</p>' +
                '<table style="width:100%;border-collapse:collapse;font-size:13px;">' +
                '<tr><td style="color:#888;padding:6px 0;width:120px;">Booking #</td>' +
                '<td style="font-weight:600;">' + b.Name + '</td></tr>' +
                '<tr><td style="color:#888;padding:6px 0;">Employee</td>' +
                '<td>' + b.Employee_Name__c + '</td></tr>' +
                '<tr><td style="color:#888;padding:6px 0;">Start Time</td>' +
                '<td>' + startStr + '</td></tr>' +
                '<tr><td style="color:#888;padding:6px 0;">End Time</td>' +
                '<td>' + endStr + '</td></tr>' +
                '</table>' +
                '<hr style="border:none;border-top:1px solid #eee;margin:16px 0;">' +
                '<p style="font-size:13px;color:#444;">To approve or reject, open the ' +
                '<strong>Meeting Room Booking System</strong> → <strong>Approvals tab</strong>.' +
                '</p>' +
                '<a href="' + approveUrl + '" style="display:inline-block;padding:10px 24px;' +
                'background:#032d60;color:#fff;text-decoration:none;border-radius:4px;' +
                'font-weight:600;font-size:14px;margin-top:8px;">Open Approvals</a>' +
                '<p style="font-size:12px;color:#aaa;margin-top:16px;">' +
                'Automated notification from Meeting Room Booking System.</p>' +
                '</div></div>';

            List<OrgWideEmailAddress> owas = [SELECT Id FROM OrgWideEmailAddress LIMIT 1];
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ manager.Email });
            mail.setSubject('Approval Required: ' + roomName + ' — ' + b.Name);
            mail.setHtmlBody(html);
            mail.setSaveAsActivity(false);
            if (!owas.isEmpty()) mail.setOrgWideEmailAddressId(owas[0].Id);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
            System.debug('Approval request email sent to: ' + manager.Email);
        } catch (Exception e) {
            System.debug('sendApprovalRequestEmail error: ' + e.getMessage());
        }
    }

    // ── Check if current user is an approver ─────────────────────────────────
    @AuraEnabled(cacheable=true)
    public static Boolean isCurrentUserApprover() {
        // 1. Check if user has any pending workitems assigned to them
        List<ProcessInstanceWorkitem> items = [
            SELECT Id FROM ProcessInstanceWorkitem
            WHERE Actor.Id = :UserInfo.getUserId()
              AND ProcessInstance.Status = 'Pending'
              AND ProcessInstance.TargetObject.Type = 'Booking__c'
            LIMIT 1
        ];
        if (!items.isEmpty()) return true;

        // 2. Check permission sets
        List<PermissionSetAssignment> perms = [
            SELECT Id FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
              AND PermissionSet.Name IN ('BookingAdmin', 'Booking_Manager')
            LIMIT 1
        ];
        if (!perms.isEmpty()) return true;

        // 3. Check if user is a manager of someone (any user has them as manager)
        List<User> subordinates = [
            SELECT Id FROM User
            WHERE ManagerId = :UserInfo.getUserId()
            AND IsActive = true
            LIMIT 1
        ];
        if (!subordinates.isEmpty()) return true;

        // 4. Check profile name — handles System Admin and custom admin profiles
        User currentUser = [SELECT Profile.Name FROM User
                            WHERE Id = :UserInfo.getUserId() LIMIT 1];
        return currentUser.Profile.Name.containsIgnoreCase('Admin');
    }

    // ── LWC: get pending approvals for current user's items ───────────────────
    @AuraEnabled(cacheable=false)
    public static List<ApprovalWrapper> getPendingApprovals() {
        List<ApprovalWrapper> out = new List<ApprovalWrapper>();
        try {
            Id currentUserId = UserInfo.getUserId();

            // Strictly show only workitems assigned to the current user
            List<ProcessInstanceWorkitem> workItems = [
                SELECT Id, Actor.Name, Actor.Id,
                       ProcessInstance.Id, ProcessInstance.TargetObjectId,
                       ProcessInstance.Status
                FROM ProcessInstanceWorkitem
                WHERE ProcessInstance.TargetObject.Type = 'Booking__c'
                  AND ProcessInstance.Status = 'Pending'
                  AND Actor.Id = :currentUserId
                ORDER BY CreatedDate DESC
                LIMIT 50
            ];

            Set<Id> bookingIds = new Set<Id>();
            for (ProcessInstanceWorkitem wi : workItems) {
                bookingIds.add(wi.ProcessInstance.TargetObjectId);
            }

            if (bookingIds.isEmpty()) return out;

            Map<Id, Booking__c> bookings = new Map<Id, Booking__c>([
                SELECT Id, Name, Room_Name__r.Name, Employee_Name__c,
                       Start_Time__c, End_Time__c, Status__c
                FROM Booking__c
                WHERE Id IN :bookingIds
                AND Status__c = 'Pending Approval'
            ]);

            // Deduplicate — one entry per booking (latest workitem)
            Set<Id> seen = new Set<Id>();
            String tzId = 'Asia/Kolkata'; // always use org timezone (IST) — not user's local tz
            for (ProcessInstanceWorkitem wi : workItems) {
                Id bId = wi.ProcessInstance.TargetObjectId;
                if (seen.contains(bId)) continue;
                seen.add(bId);
                Booking__c b = bookings.get(bId);
                if (b == null) continue;
                String actorName = wi.Actor != null ? wi.Actor.Name : '';
                out.add(new ApprovalWrapper(b, wi.ProcessInstance.Id, actorName, tzId));
            }
        } catch (Exception e) {
            System.debug('getPendingApprovals error: ' + e.getMessage());
        }
        return out;
    }

    // ── LWC: approve or reject ────────────────────────────────────────────────
    @AuraEnabled
    public static void processApproval(String bookingId, String action, String comments) {
        try {
            Id currentUserId = UserInfo.getUserId();

            // Strictly enforce: only the assigned actor can approve or reject
            List<ProcessInstanceWorkitem> workItems = [
                SELECT Id, Actor.Id, Actor.Name
                FROM ProcessInstanceWorkitem
                WHERE ProcessInstance.TargetObjectId = :bookingId
                  AND ProcessInstance.Status = 'Pending'
                  AND Actor.Id = :currentUserId
                LIMIT 1
            ];

            if (workItems.isEmpty()) {
                throw new AuraHandledException('You are not the assigned approver for this booking.');
            }

            // Process only the FIRST pending workitem for this booking
            // The approval process handles step progression automatically
            Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
            req.setWorkitemId(workItems[0].Id);
            req.setAction(action);
            if (String.isNotBlank(comments)) req.setComments(comments);
            Approval.ProcessResult result = Approval.process(req);
            System.debug('Approval processed: ' + result.isSuccess());
            if (!result.isSuccess()) {
                throw new AuraHandledException('Approval processing failed: ' + result.getErrors());
            }

            // Update custom Status__c field — Salesforce approval process does NOT do this automatically
            if (action == 'Approve') {
                update new Booking__c(Id = bookingId, Status__c = 'Approved');
            }

            // Send notification email to the original booker
            sendApprovalResultEmail(bookingId, action, comments);

            // If rejected — delete the booking so the slot is freed immediately
            if (action == 'Reject') {
                try {
                    delete [SELECT Id FROM Booking__c WHERE Id = :bookingId LIMIT 1];
                } catch (Exception delEx) {
                    System.debug('Could not delete rejected booking: ' + delEx.getMessage());
                }
            }

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Error processing approval: ' + e.getMessage());
        }
    }

    // ── Send result email to booker ───────────────────────────────────────────
    private static void sendApprovalResultEmail(String bookingId, String action, String comments) {
        try {
            Booking__c b = [
                SELECT Name, Room_Name__r.Name, Employee_Name__c,
                       Start_Time__c, End_Time__c, Meeting_Link__c,
                       CreatedById
                FROM Booking__c WHERE Id = :bookingId LIMIT 1
            ];

            User booker = [SELECT Email, Name FROM User WHERE Id = :b.CreatedById LIMIT 1];
            String tzId     = 'Asia/Kolkata'; // always use org timezone (IST) — not user's local tz
            String startStr = b.Start_Time__c.format('dd-MM-yyyy hh:mm a', tzId);
            String roomName = b.Room_Name__r != null ? b.Room_Name__r.Name : 'Board Room';
            Boolean approved = action == 'Approve';

            String subject = approved
                ? 'Booking Approved: ' + roomName + ' — ' + startStr
                : 'Booking Rejected: ' + roomName + ' — ' + startStr;

            String color  = approved ? '#2e844a' : '#c23934';
            String status = approved ? 'APPROVED' : 'REJECTED';
            String icon   = approved ? '✅' : '❌';

            String joinBtn = approved && String.isNotBlank(b.Meeting_Link__c)
                ? '<a href="' + b.Meeting_Link__c + '" style="display:inline-block;padding:10px 24px;' +
                  'background:#0176d3;color:#fff;text-decoration:none;border-radius:4px;' +
                  'font-weight:600;margin-top:12px;">📹 Join Meeting</a>'
                : '';

            String commentBlock = String.isNotBlank(comments)
                ? '<p style="margin:12px 0 0;padding:10px;background:#f4f6f9;border-radius:4px;' +
                  'font-size:13px;color:#444;"><strong>Comments:</strong> ' + comments + '</p>'
                : '';

            String html =
                '<div style="font-family:Arial,sans-serif;max-width:500px;margin:0 auto;">' +
                '<div style="background:' + color + ';padding:20px 28px;border-radius:8px 8px 0 0;">' +
                '<h2 style="color:#fff;margin:0;">' + icon + ' Booking ' + status + '</h2></div>' +
                '<div style="background:#fff;border:1px solid #e3e6ea;border-top:none;' +
                'padding:24px 28px;border-radius:0 0 8px 8px;">' +
                '<table style="width:100%;font-size:13px;border-collapse:collapse;">' +
                '<tr><td style="color:#888;padding:6px 0;width:110px;">Booking #</td>' +
                '<td style="font-weight:600;">' + b.Name + '</td></tr>' +
                '<tr><td style="color:#888;padding:6px 0;">Room</td>' +
                '<td>' + roomName + '</td></tr>' +
                '<tr><td style="color:#888;padding:6px 0;">Time</td>' +
                '<td>' + startStr + '</td></tr>' +
                '<tr><td style="color:#888;padding:6px 0;">Approved by</td>' +
                '<td>' + UserInfo.getName() + '</td></tr>' +
                '</table>' +
                commentBlock + joinBtn +
                '</div></div>';

            List<OrgWideEmailAddress> owas = [SELECT Id FROM OrgWideEmailAddress LIMIT 1];
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ booker.Email });
            mail.setSubject(subject);
            mail.setHtmlBody(html);
            mail.setSaveAsActivity(false);
            if (!owas.isEmpty()) mail.setOrgWideEmailAddressId(owas[0].Id);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
        } catch (Exception e) {
            System.debug('Result email error: ' + e.getMessage());
        }
    }

    // ── Wrapper ───────────────────────────────────────────────────────────────
    public class ApprovalWrapper {
        @AuraEnabled public String Id;
        @AuraEnabled public String BookingId;
        @AuraEnabled public String BookingName;
        @AuraEnabled public String RoomName;
        @AuraEnabled public String EmployeeName;
        @AuraEnabled public String StartTime;
        @AuraEnabled public String EndTime;
        @AuraEnabled public String PendingWith;
        @AuraEnabled public String ProcessInstanceId;

        public ApprovalWrapper(Booking__c b, Id piId, String actor, String tzId) {
            this.BookingId          = b.Id;
            this.BookingName        = b.Name;
            this.RoomName           = b.Room_Name__r != null ? b.Room_Name__r.Name : '';
            this.EmployeeName       = b.Employee_Name__c;
            this.StartTime          = b.Start_Time__c.format('dd-MM-yyyy hh:mm a', tzId);
            this.EndTime            = b.End_Time__c.format('hh:mm a', tzId);
            this.PendingWith        = actor;
            this.ProcessInstanceId  = piId;
        }
    }
}