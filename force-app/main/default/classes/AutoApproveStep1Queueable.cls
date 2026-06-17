public class AutoApproveStep1Queueable implements Queueable {
    private Id bookingId;
    private Id submitterId; // pass submitter ID explicitly — Queueable runs as system

    public AutoApproveStep1Queueable(Id bookingId, Id submitterId) {
        this.bookingId   = bookingId;
        this.submitterId = submitterId;
    }

    public void execute(QueueableContext ctx) {
        try {
            System.debug('Queueable executing for booking: ' + bookingId +
                         ' submitter: ' + submitterId);

            // Step 1 — auto-approve if assigned to submitter
            List<ProcessInstanceWorkitem> items = [
                SELECT Id, Actor.Id, Actor.Name
                FROM ProcessInstanceWorkitem
                WHERE ProcessInstance.TargetObjectId = :bookingId
                  AND ProcessInstance.Status = 'Pending'
                ORDER BY CreatedDate ASC
            ];

            System.debug('Work items: ' + items.size());
            for (ProcessInstanceWorkitem wi : items) {
                System.debug('Actor: ' + wi.Actor.Name + ' match: ' + (wi.Actor.Id == submitterId));
                if (wi.Actor.Id == submitterId) {
                    Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
                    req.setWorkitemId(wi.Id);
                    req.setAction('Approve');
                    req.setComments('Auto-approved — escalating to manager');
                    Approval.ProcessResult r = Approval.process(req);
                    System.debug('Auto-approve: ' + r.isSuccess());
                    break;
                }
            }

            // Step 2 — send email to manager
            // Get manager from submitter
            User booker = [SELECT Id, Name, ManagerId FROM User
                           WHERE Id = :submitterId LIMIT 1];
            System.debug('Booker: ' + booker.Name + ' ManagerId: ' + booker.ManagerId);

            if (booker.ManagerId == null) {
                System.debug('No manager — skipping email');
                return;
            }

            User manager = [SELECT Id, Name, Email FROM User
                            WHERE Id = :booker.ManagerId LIMIT 1];
            System.debug('Sending email to: ' + manager.Email);

            Booking__c b = [
                SELECT Id, Name, Room_Name__r.Name, Employee_Name__c,
                       Start_Time__c, End_Time__c
                FROM Booking__c WHERE Id = :bookingId LIMIT 1
            ];

            TimeZone tz  = TimeZone.getTimeZone('Asia/Kolkata');
            String startStr = b.Start_Time__c.format('dd-MM-yyyy hh:mm a', tz.getID());
            String endStr   = b.End_Time__c.format('hh:mm a', tz.getID());
            String roomName = b.Room_Name__r != null ? b.Room_Name__r.Name : 'Board Room';
            String orgUrl   = System.URL.getOrgDomainUrl().toExternalForm();

            String html =
                '<div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;">' +
                '<div style="background:#032d60;padding:20px 28px;border-radius:8px 8px 0 0;">' +
                '<h2 style="color:#fff;margin:0;">&#128203; Approval Required — Board Room</h2>' +
                '</div>' +
                '<div style="background:#fff;border:1px solid #e3e6ea;border-top:none;' +
                'padding:24px 28px;border-radius:0 0 8px 8px;">' +
                '<p style="font-size:14px;color:#444;margin-bottom:16px;">' +
                'Hi ' + manager.Name + ',<br><br>' +
                '<strong>' + b.Employee_Name__c + '</strong> has requested to book ' +
                '<strong>' + roomName + '</strong> and requires your approval.</p>' +
                '<table style="width:100%;border-collapse:collapse;font-size:13px;">' +
                '<tr><td style="color:#888;padding:6px 0;width:110px;">Booking #</td>' +
                '<td style="font-weight:600;">' + b.Name + '</td></tr>' +
                '<tr><td style="color:#888;padding:6px 0;">Employee</td>' +
                '<td>' + b.Employee_Name__c + '</td></tr>' +
                '<tr><td style="color:#888;padding:6px 0;">Start Time</td>' +
                '<td>' + startStr + '</td></tr>' +
                '<tr><td style="color:#888;padding:6px 0;">End Time</td>' +
                '<td>' + endStr + '</td></tr>' +
                '</table>' +
                '<hr style="border:none;border-top:1px solid #eee;margin:16px 0;">' +
                '<p style="font-size:13px;color:#444;">Open the Approvals tab to approve or reject:</p>' +
                '<a href="' + orgUrl + '" style="display:inline-block;padding:10px 24px;' +
                'background:#032d60;color:#fff;text-decoration:none;border-radius:4px;' +
                'font-weight:600;font-size:14px;margin-top:8px;">&#10003; Open Approvals</a>' +
                '<p style="font-size:12px;color:#aaa;margin-top:16px;">' +
                'Automated notification — Meeting Room Booking System.</p>' +
                '</div></div>';

            List<OrgWideEmailAddress> owas = [SELECT Id FROM OrgWideEmailAddress LIMIT 1];
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String>{ manager.Email });
            mail.setSubject('Approval Required: ' + roomName + ' — ' + b.Name);
            mail.setHtmlBody(html);
            mail.setSaveAsActivity(false);
            if (!owas.isEmpty()) mail.setOrgWideEmailAddressId(owas[0].Id);

            Messaging.SendEmailResult[] results =
                Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
            System.debug('Email sent: ' + results[0].isSuccess() +
                         ' errors: ' + results[0].getErrors());

        } catch (Exception e) {
            System.debug('Queueable error: ' + e.getMessage() +
                         ' stack: ' + e.getStackTraceString());
        }
    }
}