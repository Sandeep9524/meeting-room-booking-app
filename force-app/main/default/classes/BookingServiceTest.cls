/**
 * @description Test class for BookingService
 * @group Test Classes
 */
@isTest
private class BookingServiceTest {
    
    /**
     * @description Test getBookingStatus returns correct value
     */
    @isTest
    static void shouldReturnBooked_WhenGetBookingStatusCalled() {
        // Given
        String expectedStatus = 'Booked';
        
        // When
        Test.startTest();
        String actualStatus = BookingService.getBookingStatus();
        Test.stopTest();
        
        // Then
        Assert.areEqual(expectedStatus, actualStatus, 
            'getBookingStatus should return "Booked"');
    }
    
    /**
     * @description Test getBookingStatus returns non-null value
     */
    @isTest
    static void shouldReturnNonNullValue_WhenGetBookingStatusCalled() {
        // When
        Test.startTest();
        String status = BookingService.getBookingStatus();
        Test.stopTest();
        
        // Then
        Assert.isNotNull(status, 
            'getBookingStatus should not return null');
        Assert.isTrue(status.length() > 0, 
            'getBookingStatus should return a non-empty string');
    }
    
    /**
     * @description Test multiple calls return consistent value
     */
    @isTest
    static void shouldReturnConsistentValue_WhenCalledMultipleTimes() {
        // When
        Test.startTest();
        String status1 = BookingService.getBookingStatus();
        String status2 = BookingService.getBookingStatus();
        String status3 = BookingService.getBookingStatus();
        Test.stopTest();
        
        // Then
        Assert.areEqual(status1, status2, 
            'Multiple calls should return the same value');
        Assert.areEqual(status2, status3, 
            'Multiple calls should return the same value');
        Assert.areEqual('Booked', status1, 
            'All calls should return "Booked"');
    }
}