import { LightningElement, track, wire } from 'lwc';
import getBookings from '@salesforce/apex/BookingController.getBookings';
import getRooms from '@salesforce/apex/BookingController.getRooms';
import checkAvailabilityApex from '@salesforce/apex/BookingController.checkAvailability';
import createBookingApex  from '@salesforce/apex/BookingController.createBooking';
import cancelBookingApex from '@salesforce/apex/BookingController.cancelBooking';
import getAllAuditLogs   from '@salesforce/apex/BookingAuditHandler.getAllAuditLogs';
import getAuditLogCount  from '@salesforce/apex/BookingAuditHandler.getAuditLogCount';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class MeetingRoomBooking extends LightningElement {
  @track activeTab   = 'calendar';
  @track gridStyle   = '';
  @track selectedDate = '';
  @track selectedRoom = '';
  @track timeSlots    = [];
  @track displayRooms = [];
  @track roomsMap     = new Map();

  @track formData = {
    roomId: '', employeeName: '',
    startDate: '', startTime24: '',
    endDate:   '', endTime24:   ''
  };

  @track bookings        = [];
  @track conflictMessage = '';
  @track successMessage  = '';
  @track preselectedSlot = null;
  @track isLoading  = false;
  @track isCreating = false;
  @track showFlow   = false;

  // ── Audit log state ───────────────────────────────────────────────────────
  @track auditLogs       = [];
  @track auditTotalCount = 0;
  @track auditPage       = 1;
  auditPageSize          = 20;
  @track auditFilter     = { action: 'All', user: '', date: '' };


  wiredRoomsResult;

  // columns kept for reference — table is now custom HTML for cancel button support
  @track cancellingId   = null;
  @track bookingSearch  = '';
  @track sortCol        = 'DisplayStart'; // default sort by start time
  @track sortDir        = 'asc';

  get hasBookings() { return this.bookings && this.bookings.length > 0; }

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  connectedCallback() {
    this.isLoading = true;
    const d = new Date();
    const p = n => String(n).padStart(2, '0');
    this.selectedDate = `${d.getFullYear()}-${p(d.getMonth()+1)}-${p(d.getDate())}`;
  }

  // ── Wire: rooms (cacheable=true is fine — rooms rarely change) ────────────
  @wire(getRooms)
  wiredRooms(result) {
    this.wiredRoomsResult = result;
    if (result.data) {
      this.displayRooms = result.data;
      result.data.forEach(r => this.roomsMap.set(r.value, r.label));
      this.computeGridStyle();
      this.generateTimeSlots();
      this.loadBookings();          // load bookings once rooms are ready
    } else if (result.error) {
      this.showToast('Error', 'Failed to load rooms', 'error');
      this.isLoading = false;
    }
  }

  // ── Bookings: imperative call so we always get fresh data ─────────────────
  loadBookings() {
    this.isLoading = true;
    getBookings()
      .then(data => {
        this.bookings = (data || []).map(b => ({
          ...b,
          statusClass: 'status-booked',
          canCancel:   true   // all returned records are Booked (canceled = deleted)
        }));
        this.generateCalendarView();
      })
      .catch(() => {
        this.showToast('Error', 'Failed to load bookings', 'error');
      })
      .finally(() => { this.isLoading = false; });
  }

  // ── Time slots 08:00–18:00 every 30 min ──────────────────────────────────
  generateTimeSlots() {
    const slots = [];
    for (let h = 8; h < 18; h++) {
      for (let m = 0; m < 60; m += 30) {
        const t24  = `${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}`;
        const h12  = h > 12 ? h - 12 : (h === 0 ? 12 : h);
        const ampm = h >= 12 ? 'PM' : 'AM';
        slots.push({ time: t24, label: `${h12}:${String(m).padStart(2,'0')} ${ampm}`, cells: this.createCellsForRooms() });
      }
    }
    this.timeSlots = slots;
    this.computeGridStyle();
  }

  createCellsForRooms() {
    const cells = {};
    this.displayRooms.forEach(r => {
      cells[r.value] = { cssClass: 'calendar-cell available', isBooked: false, tooltip: 'Available', bookingTitle: '', timeRange: '' };
    });
    return cells;
  }

  computeGridStyle() {
    const roomCount = Math.max((this.filteredRooms || []).length, 1);
    const cols = ['minmax(70px, 70px)'];
    for (let i = 0; i < roomCount; i++) cols.push('minmax(120px, 1fr)');
    this.gridStyle = `grid-template-columns: ${cols.join(' ')};`;
  }

  // ── Calendar render ───────────────────────────────────────────────────────
  generateCalendarView() {
    if (!this.displayRooms.length || !this.timeSlots.length) return;
    this.isLoading = true;

    // Reset cells
    this.timeSlots = this.timeSlots.map(s => ({ ...s, cells: this.createCellsForRooms() }));

    // Paint bookings onto cells
    // Use StartLocal/EndLocal ("YYYY-MM-DD HH:mm" in org TZ from Apex) — no JS timezone math
    (this.bookings || []).filter(b => b.Status === 'Booked').forEach(b => { // skip canceled
      if (!b.StartLocal || !b.EndLocal) return;

      // StartLocal format: "YYYY-MM-DD HH:mm"
      const [startDatePart, startTimePart] = b.StartLocal.split(' ');
      const [endDatePart,   endTimePart]   = b.EndLocal.split(' ');

      const [bY, bM, bD]   = startDatePart.split('-').map(Number);
      const [sY, sM, sD]   = this._parseDateParts(this.selectedDate);

      if (bY === sY && bM === sM && bD === sD) {
        const [startH, startMin] = startTimePart.split(':').map(Number);
        const [endH,   endMin]   = endTimePart.split(':').map(Number);
        // Convert to minutes-since-midnight for easy overlap comparison
        const bookingStartMins = startH * 60 + startMin;
        const bookingEndMins   = endH   * 60 + endMin;

        this.timeSlots.forEach(slot => {
          const [sh, smin] = slot.time.split(':').map(Number);
          const slotStartMins = sh * 60 + smin;
          const slotEndMins   = slotStartMins + 30;

          if (bookingStartMins < slotEndMins && bookingEndMins > slotStartMins && slot.cells[b.RoomId]) {
            slot.cells[b.RoomId] = {
              cssClass: 'calendar-cell booked',
              isBooked: true,
              bookingTitle: b.EmployeeName || 'Booked',
              timeRange: `${b.DisplayStart.split(' ').slice(1).join(' ')} - ${b.DisplayEnd.split(' ').slice(1).join(' ')}`,
              tooltip: `${b.RoomName} - ${b.EmployeeName || 'Booked'}`
            };
          }
        });
      }
    });

    // Build roomCells array for template
    this.timeSlots = this.timeSlots.map(slot => ({
      ...slot,
      roomCells: (this.filteredRooms || []).map(r => {
        const cell = slot.cells[r.value] || { cssClass: 'calendar-cell available', isBooked: false, tooltip: 'Available', bookingTitle: '', timeRange: '' };
        return { ...cell, roomId: r.value, roomLabel: r.label, computedClass: `room-cell ${cell.cssClass}` };
      })
    }));

    this.computeGridStyle();
    this.isLoading = false;
  }

  formatTime(date) {
    return date.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit', hour12: true, timeZone: 'Asia/Kolkata' });
  }

  // ── Event handlers ────────────────────────────────────────────────────────
  handleTabChange(e) {
    this.activeTab = e.target.value;
    this.conflictMessage = '';
    this.successMessage  = '';
    if (this.activeTab === 'calendar') this.loadBookings();
    if (this.activeTab === 'audit') {
      this.auditPage = 1;
      // Default date filter to today if not already set
      if (!this.auditFilter.date) {
        const d = new Date();
        const p = n => String(n).padStart(2,'0');
        this.auditFilter = { ...this.auditFilter,
          date: d.getFullYear() + '-' + p(d.getMonth()+1) + '-' + p(d.getDate()) };
      }
      this.loadAuditLogs();
    }
  }

  handleDateChange(e) {
    // input type="date" should return YYYY-MM-DD per spec but normalise just in case
    this.selectedDate = this._normaliseDate(e.target.value);
    this.generateCalendarView();
  }

  handleRoomChange(e) {
    this.selectedRoom = e.target.value;
    this.computeGridStyle();
    this.generateCalendarView();
  }

  handleTodayClick() {
    const d = new Date();
    const p = n => String(n).padStart(2, '0');
    this.selectedDate = `${d.getFullYear()}-${p(d.getMonth()+1)}-${p(d.getDate())}`; // always YYYY-MM-DD
    this.computeGridStyle();
    this.generateCalendarView();
  }

  handleSlotClick(event) {
    const roomId = event.currentTarget.dataset.room;
    const time   = event.currentTarget.dataset.time;
    const slot   = this.timeSlots.find(s => s.time === time);
    if (slot?.cells?.[roomId]?.isBooked) {
      this.showToast('Unavailable', 'This time slot is already booked', 'warning');
      return;
    }

    // Block clicks on past slots — compare using numeric parts (immune to date format)
    const [selY, selM, selD] = this._parseDateParts(this.selectedDate);
    const [slotH, slotMin]   = time.split(':').map(Number);
    const now    = new Date();
    const toInt  = (y,m,d,h,mn) => y*100000000 + m*1000000 + d*10000 + h*100 + mn;
    const slotInt = toInt(selY, selM, selD, slotH, slotMin);
    const nowInt  = toInt(now.getFullYear(), now.getMonth()+1, now.getDate(), now.getHours(), now.getMinutes());
    if (slotInt < nowInt) {
      this.showToast('Unavailable', 'Cannot book a slot in the past', 'warning');
      return;
    }
    const roomLabel = this.roomsMap.get(roomId);
    const timeLabel = this.timeSlots.find(s => s.time === time)?.label;
    this.preselectedSlot = { roomId, room: roomLabel, date: this.selectedDate, time, timeLabel };
    this.formData.roomId = roomId;

    const [hr, mn] = time.split(':').map(Number);
    const endTotal = hr * 60 + mn + 30;
    const p = n => String(n).padStart(2, '0');
    this.formData.startDate   = this.selectedDate;
    this.formData.startTime24 = `${p(hr)}:${p(mn)}`;
    this.formData.endDate     = this.selectedDate;
    this.formData.endTime24   = `${p(Math.floor(endTotal/60))}:${p(endTotal%60)}`;
    this.activeTab = 'create';
    this.showToast('Time Selected', `${roomLabel} at ${timeLabel}`, 'info');
  }

  clearPreselection() {
    this.preselectedSlot = null;
    this.formData = { roomId: '', employeeName: '', startDate: '', startTime24: '', endDate: '', endTime24: '' };
  }

  handleFormChange(e) {
    this.formData[e.target.dataset.field] = e.target.value || '';
    this.conflictMessage = '';
    this.successMessage  = '';
  }

  handleRawInputChange(e) {
    const field = e.target.dataset.field;
    const raw   = e.target.value || '';
    this.formData[field] = (field === 'startTime24' || field === 'endTime24') ? raw.substring(0, 5) : raw;
    this.conflictMessage = '';
    this.successMessage  = '';
  }

  handleRoomPick(e) {
    this.formData.roomId = e.detail.value || '';
    this.conflictMessage = '';
    this.successMessage  = '';
  }

  _toApexLocalStr(dateStr, timeStr) { return `${dateStr} ${timeStr}:00`; }

  validateForm() {
    if (!this.formData.roomId || (!this.showFlow && !this.formData.employeeName) ||
        !this.formData.startDate || !this.formData.startTime24 ||
        !this.formData.endDate   || !this.formData.endTime24) {
      this.showToast('Validation Error', 'Please fill in all required fields', 'error');
      return false;
    }

    // Parse all date parts as numbers — immune to dd-MM-yyyy vs YYYY-MM-DD format
    const [sY, sM, sD] = this._parseDateParts(this.formData.startDate);
    const [eY, eM, eD] = this._parseDateParts(this.formData.endDate);
    const [sH, sMin]   = this.formData.startTime24.split(':').map(Number);
    const [eH, eMin]   = this.formData.endTime24.split(':').map(Number);

    const now  = new Date();
    const nowY = now.getFullYear(), nowM = now.getMonth()+1, nowD = now.getDate();
    const nowH = now.getHours(),    nowMin = now.getMinutes();

    // Convert to comparable integers: YYYYMMDDHHMM
    const toInt = (y,m,d,h,min) => y*100000000 + m*1000000 + d*10000 + h*100 + min;
    const startInt = toInt(sY, sM, sD, sH, sMin);
    const endInt   = toInt(eY, eM, eD, eH, eMin);
    const nowInt   = toInt(nowY, nowM, nowD, nowH, nowMin);

    // Bug 1 fix: reject past bookings
    if (startInt < nowInt) {
      this.showToast('Validation Error', 'Cannot book a slot in the past', 'error');
      return false;
    }

    // Bug 2 fix: start and end must be on the same day
    if (sY !== eY || sM !== eM || sD !== eD) {
      this.showToast('Validation Error', 'Start and end must be on the same day', 'error');
      return false;
    }

    // End must be after start
    if (endInt <= startInt) {
      this.showToast('Validation Error', 'End time must be after start time', 'error');
      return false;
    }

    return true;
  }


  async checkAvailability() {
    if (!this.validateForm()) return;
    this.isLoading = true; this.conflictMessage = '';
    try {
      const ok = await checkAvailabilityApex({
        roomId:    this.formData.roomId,
        startTime: this._toApexLocalStr(this.formData.startDate, this.formData.startTime24),
        endTime:   this._toApexLocalStr(this.formData.endDate,   this.formData.endTime24)
      });
      if (ok) this.showToast('Available', 'The room is available', 'success');
      else     this.conflictMessage = 'Already booked for this time. Please choose another slot.';
    } catch (e) {
      this.showToast('Error', e.body?.message || 'Failed to check availability', 'error');
    } finally { this.isLoading = false; }
  }

  async createBooking() {
    if (!this.validateForm()) return;
    this.isCreating = true; this.conflictMessage = ''; this.successMessage = '';
    try {
      await createBookingApex({
        roomId:       this.formData.roomId,
        employeeName: this.formData.employeeName,
        startTime:    this._toApexLocalStr(this.formData.startDate, this.formData.startTime24),
        endTime:      this._toApexLocalStr(this.formData.endDate,   this.formData.endTime24)
      });
      this.successMessage = 'Booking created successfully!';
      this.showToast('Success', 'Meeting room booked successfully', 'success');
      setTimeout(() => {
        this.clearPreselection();
        this.activeTab = 'calendar';
        this.loadBookings();
      }, 1200);
    } catch (e) {
      this.showToast('Error', e.body?.message || 'Failed to create booking', 'error');
    } finally { this.isCreating = false; }
  }

  refreshBookings() { this.loadBookings(); }

  get roomOptions()   { return this.displayRooms || []; }
  get filteredRooms() {
    if (!this.selectedRoom) return this.displayRooms || [];
    return (this.displayRooms || []).filter(r => r.value === this.selectedRoom);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  // Normalise any date string to YYYY-MM-DD.
  // Handles: YYYY-MM-DD (spec), DD-MM-YYYY (some locales), MM/DD/YYYY (US).
  _normaliseDate(str) {
    if (!str) return '';
    // Already YYYY-MM-DD
    if (/^\d{4}-\d{2}-\d{2}$/.test(str)) return str;
    // DD-MM-YYYY
    if (/^\d{2}-\d{2}-\d{4}$/.test(str)) {
      const [d, m, y] = str.split('-');
      return `${y}-${m}-${d}`;
    }
    // MM/DD/YYYY
    if (/^\d{2}\/\d{2}\/\d{4}$/.test(str)) {
      const [m, d, y] = str.split('/');
      return `${y}-${m}-${d}`;
    }
    return str; // fallback — return as-is
  }

  // Parse a date string (any supported format) into [year, month, day] numbers.
  _parseDateParts(str) {
    const normalised = this._normaliseDate(str);
    return normalised.split('-').map(Number); // [YYYY, MM, DD]
  }

  // ── Audit log ─────────────────────────────────────────────────────────────

  get auditActionOptions() {
    return [
      { label: 'All Actions', value: 'All' },
      { label: 'Created',     value: 'Created' },
      { label: 'Updated',     value: 'Updated' },
      { label: 'Cancelled',   value: 'Cancelled' },
      { label: 'Deleted',     value: 'Deleted' },
      { label: 'Restored',    value: 'Restored' }
    ];
  }

  get hasAuditLogs()    { return this.auditLogs && this.auditLogs.length > 0; }
  get auditTotalPages() { return Math.max(1, Math.ceil(this.auditTotalCount / this.auditPageSize)); }
  get isFirstAuditPage(){ return this.auditPage <= 1; }
  get isLastAuditPage() { return this.auditPage >= this.auditTotalPages; }

  handleAuditFilterChange(e) {
    const field = e.target.dataset.field;
    this.auditFilter = { ...this.auditFilter, [field]: e.target.value || '' };
  }

  handleAuditDateChange(e) {
    // Normalise to YYYY-MM-DD — Apex SOQL date literals require this format
    const raw = e.target.value || '';
    this.auditFilter = { ...this.auditFilter, date: this._normaliseDate(raw) };
  }

  clearAuditFilters() {
    this.auditFilter = { action: 'All', user: '', date: '' };
    this.auditPage   = 1;
    this.loadAuditLogs();
  }

  auditPrevPage() { if (this.auditPage > 1) { this.auditPage--; this.loadAuditLogs(); } }
  auditNextPage() { if (this.auditPage < this.auditTotalPages) { this.auditPage++; this.loadAuditLogs(); } }

  loadAuditLogs() {
    this.isLoading = true;
    const offset = (this.auditPage - 1) * this.auditPageSize;
    Promise.all([
      getAllAuditLogs({
        pageSize:     this.auditPageSize,
        pageOffset:   offset,
        filterAction: this.auditFilter.action,
        filterUser:   this.auditFilter.user,
        filterDate:   this._normaliseDate(this.auditFilter.date) // always YYYY-MM-DD for SOQL
      }),
      getAuditLogCount({
        filterAction: this.auditFilter.action,
        filterUser:   this.auditFilter.user,
        filterDate:   this._normaliseDate(this.auditFilter.date)
      })
    ])
    .then(([logs, count]) => {
      this.auditTotalCount = count;
      this.auditLogs = (logs || []).map(l => ({
        ...l,
        actionBadgeClass: this._auditBadgeClass(l.Action),
        detailText:       this._auditDetail(l)
      }));
    })
    .catch(() => this.showToast('Error', 'Failed to load audit logs', 'error'))
    .finally(() => { this.isLoading = false; });
  }

  _auditBadgeClass(action) {
    const map = {
      'Created':   'audit-badge audit-badge_created',
      'Updated':   'audit-badge audit-badge_updated',
      'Cancelled': 'audit-badge audit-badge_cancelled',
      'Deleted':   'audit-badge audit-badge_deleted',
      'Restored':  'audit-badge audit-badge_restored'
    };
    return map[action] || 'audit-badge';
  }

  _auditDetail(l) {
    if (l.Action === 'Created') {
      return l.NewStartTime && l.NewEndTime
        ? l.NewStartTime + ' → ' + l.NewEndTime
        : '';
    }
    if (l.Action === 'Updated') {
      const parts = [];
      if (l.OldStartTime !== l.NewStartTime && l.NewStartTime)
        parts.push('Time: ' + (l.OldStartTime || '?') + ' → ' + l.NewStartTime);
      if (l.OldStatus !== l.NewStatus && l.NewStatus)
        parts.push('Status: ' + (l.OldStatus || '?') + ' → ' + l.NewStatus);
      return parts.join(' | ');
    }
    if (l.Action === 'Deleted' || l.Action === 'Cancelled') {
      return l.OldStartTime ? l.OldStartTime + ' → ' + (l.OldEndTime || '') : '';
    }
    return '';
  }

  // ── Cancel confirmation modal ─────────────────────────────────────────────
  @track showCancelModal  = false;
  @track cancelTargetId   = null;
  @track cancelTargetName = null;

  handleCancelBooking(event) {
    this.cancelTargetId   = event.currentTarget.dataset.id;
    this.cancelTargetName = event.currentTarget.dataset.name;
    this.showCancelModal  = true;
  }

  handleCancelModalClose() {
    this.showCancelModal  = false;
    this.cancelTargetId   = null;
    this.cancelTargetName = null;
  }

  async handleCancelConfirm() {
    this.showCancelModal = false;
    this.cancellingId    = this.cancelTargetId;
    this.isLoading       = true;
    try {
      await cancelBookingApex({ bookingId: this.cancelTargetId });
      this.showToast('Success', this.cancelTargetName + ' has been canceled and slot is now free', 'success');
      this.loadBookings();
    } catch (e) {
      this.showToast('Error', e.body?.message || 'Failed to cancel booking', 'error');
    } finally {
      this.cancellingId = null;
      this.isLoading    = false;
      this.cancelTargetId   = null;
      this.cancelTargetName = null;
    }
  }

  // ── All Bookings search + sort ───────────────────────────────────────────

  handleBookingSearch(e) {
    this.bookingSearch = e.target.value || '';
  }

  clearBookingSearch() {
    this.bookingSearch = '';
  }

  handleSort(e) {
    const col = e.currentTarget.dataset.col;
    if (this.sortCol === col) {
      this.sortDir = this.sortDir === 'asc' ? 'desc' : 'asc';
    } else {
      this.sortCol = col;
      this.sortDir = 'asc';
    }
  }

  get filteredBookings() {
    const term = (this.bookingSearch || '').toLowerCase().trim();
    let list = (this.bookings || []).filter(b => {
      if (!term) return true;
      return (b.Name         || '').toLowerCase().includes(term) ||
             (b.RoomName     || '').toLowerCase().includes(term) ||
             (b.EmployeeName || '').toLowerCase().includes(term);
    });

    // Sort
    const col = this.sortCol;
    const dir = this.sortDir === 'asc' ? 1 : -1;
    list = [...list].sort((a, b) => {
      const av = (a[col] || '').toLowerCase();
      const bv = (b[col] || '').toLowerCase();
      return av < bv ? -dir : av > bv ? dir : 0;
    });

    return list;
  }

  get filteredBookingCount() { return (this.filteredBookings || []).length; }
  get hasFilteredBookings()  { return this.filteredBookingCount > 0; }

  // Sort icons per column
  get sortIcon() {
    const cols = ['Name','RoomName','EmployeeName','DisplayStart','DisplayEnd','Status'];
    const icons = {};
    cols.forEach(c => {
      icons[c] = this.sortCol === c ? (this.sortDir === 'asc' ? ' ▲' : ' ▼') : ' ⇅';
    });
    return icons;
  }

  get sortIconClass() {
    const cols = ['Name','RoomName','EmployeeName','DisplayStart','DisplayEnd','Status'];
    const cls = {};
    cols.forEach(c => {
      cls[c] = this.sortCol === c ? 'sort-icon sort-icon_active' : 'sort-icon';
    });
    return cls;
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}