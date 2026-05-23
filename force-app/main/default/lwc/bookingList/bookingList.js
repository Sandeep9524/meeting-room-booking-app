import { LightningElement, wire } from 'lwc';
import getBookings from '@salesforce/apex/BookingController.getBookings';

export default class BookingList extends LightningElement {

    bookings;

    @wire(getBookings)
    wiredBookings({ error, data }) {

        if(data) {
            this.bookings = data;
        } else if(error) {
            console.error(error);
        }
    }
}