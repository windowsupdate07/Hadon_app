# Honda NTP — Flutter App Spec

เอกสารนี้สรุปจาก repo [`nutchapardev/honda-ntp-antigravity`](https://github.com/nutchapardev/honda-ntp-antigravity) (backend Node/Express + Sequelize/MySQL, frontend Vue 3 + Vuetify, และโฟลเดอร์ `mobile/` ที่เป็น Flutter ตั้งต้น) เพื่อใช้เป็นแบบในการสร้างแอป Flutter ตัวใหม่ในโปรเจกต์นี้

> **ข้อควรรู้ก่อนเริ่ม:** ข้อมูล API ในเอกสารนี้อ้างอิงจาก **โค้ดจริงใน `backend/routes/*`** ไม่ใช่จาก `README.md` ของ repo เพราะ README มีหลายจุดที่ไม่ตรงกับโค้ด (ดูหัวข้อ [README vs โค้ดจริง](#9-readme-vs-โค้ดจริง))
>
> **Backend ที่ใช้:** แอป Flutter เชื่อมกับ **`honda-ntp-antigravity/backend`** (เวอร์ชันล่าสุด) เท่านั้น
> **อย่าใช้ `~/Dev/Node/ntp-api`** (repo `nutchapardev/ntp-api`) — เป็น backend เวอร์ชันเก่า:
>
> - local working copy (ก.ย. 2025, ตามหลัง remote 22 commits): ~40 endpoint ไม่มี quotation, invoice flow, receipt, appointment, follow-up, dashboard, work-summary; token อายุ 24 ชม. ไม่มี `/auth/refresh`
> - `origin/main` (มี.ค. 2026): เพิ่ม quotation/PDF/invoice แล้ว แต่ยังไม่มี refresh token, receipt, appointment
>
> ถ้ารันผิดตัว endpoint ในข้อ 7 หลายตัวจะได้ `404 api not found.` และ interceptor refresh จะใช้ไม่ได้

---

## 1. ภาพรวมระบบ

ระบบบริหารอู่ซ่อมรถ Honda NTP: รับรถ → ใบเสนอราคา (+มัดจำ) → เปิดงานซ่อม + ใบแจ้งหนี้ → จัดสรรอะไหล่ → ซ่อม → บันทึกช่าง → ยืนยันใบแจ้งหนี้ → ใบเสร็จ และมีระบบคลังอะไหล่ (ซื้อเข้า/ขายหน้าร้าน), นัดหมาย, ติดตามรอบซ่อม, Dashboard

### Business flow หลัก

```
ลูกค้า (นัดหมาย / Walk-in)
  └─ เลือก/สร้างลูกค้า + ที่อยู่ → เลือก/เพิ่มรถ
      └─ สร้าง Quotation (QT-YYYYMMDD-NNN)
          ├─ เพิ่มรายการซ่อม (RepairCategory / Preset) + อะไหล่
          ├─ (ถ้ามี) CashPledge เงินมัดจำ → PDF ใบเสร็จมัดจำ
          └─ ลูกค้าอนุมัติ → POST /invoices/create-with-repair
               สร้าง Repair + Invoice (INV-YYYYMMDD-NNN) พร้อมกัน
                  └─ WorkStatus: ตรวจสอบ → จัดสรรอุปกรณ์ → ซ่อม → ซ่อมเสร็จ
                       ├─ บันทึกช่าง (RepairAttendance) → Work Summary
                       ├─ Follow-up (คำนวณวันครบรอบซ่อม)
                       └─ ยืนยัน Invoice (status 2) → Receipt → PDF
```

---

## 2. Tech Stack ที่แนะนำ

ใช้ชุดเดียวกับ `mobile/` เดิมใน repo เพื่อให้ต่อยอดและอ่านโค้ดเดิมได้ง่าย แล้วเติมส่วนที่ขาดสำหรับ auth แบบ cookie

| เรื่อง | Package | หมายเหตุ |
| --- | --- | --- |
| HTTP | `dio` | |
| Cookie (refresh token) | `dio_cookie_manager`, `cookie_jar` | **จำเป็น** — refresh token อยู่ใน HttpOnly cookie (ดูข้อ 4) |
| Routing | `go_router` | ใช้ `ShellRoute` + `redirect` ตาม auth state |
| State | `provider` (global: auth, lookups) + `setState` (local) | ตาม convention ใน `AGENT.md` |
| เก็บ token | `flutter_secure_storage` | อย่าเก็บ access token ใน `shared_preferences` |
| Path cookie jar | `path_provider` | สำหรับ `PersistCookieJar` |
| Font | `google_fonts` (K2D) | ทั้งระบบใช้ K2D |
| วันที่/ตัวเลข | `intl` (`th`) | แสดงปี พ.ศ., เงิน `#,##0.00` |
| รูปภาพ | `image_picker`, `cached_network_image` | ถ่าย/เลือกรูปรถ |
| PDF | `url_launcher` หรือ `dio` download + `open_filex` / `printing` | PDF สร้างจาก server |
| ปฏิทินนัดหมาย | `table_calendar` | หน้า Appointments |
| กราฟ Dashboard | `fl_chart` | |

---

## 3. การเชื่อมต่อ Backend

- **รัน backend:** `cd honda-ntp-antigravity/backend && npm install && node app.js` (ต้องมี MySQL `honda_ntp` และ `.env` ที่มี `API_PATH=/ntp-api`, `JWT_ENABLED=true`; seed ด้วย `node scripts/seed.js`)
- **Base URL:** `http://<host>:8080/ntp-api` (มาจาก `PORT=8080`, `API_PATH=/ntp-api`)
  - Android emulator: `http://10.0.2.2:8080/ntp-api`
  - เครื่องจริงผ่าน USB: `adb reverse tcp:8080 tcp:8080` แล้วใช้ `http://127.0.0.1:8080/ntp-api`
  - ให้ตั้งผ่าน `--dart-define=API_BASE_URL=...` ไม่ hardcode
- **Dev ใช้ HTTP:** ต้องเปิด cleartext — Android `android:usesCleartextTraffic="true"` (เฉพาะ debug), iOS `NSAppTransportSecurity` exception
- **Header auth:** `x-access-token: <accessToken>` (ไม่ใช่ `Authorization: Bearer`)
- **Server ยังรับ token ทาง query ได้:** `?token=<accessToken>` — ใช้กับการเปิด PDF/รูปใน browser หรือ `Image.network`
- CORS ไม่กระทบ native app แต่ถ้าจะทำ Flutter Web ต้องเพิ่ม origin ใน `backend/app.js`

### รูปแบบ Response (ไม่สม่ำเสมอ — ต้องจัดการใน client)

| กรณี | รูปแบบ |
| --- | --- |
| GET list / GET by id (crud) | **array หรือ object ตรงๆ** ไม่มี wrapper |
| POST create (crud) | `201 { result: true, data }` |
| Error ส่วนใหญ่ | **`200 { result: false, message }`** ← HTTP 200 แต่ล้มเหลว |
| Login | `200 { result, message, employeeData, accessToken }` |
| Token หมดอายุ/ผิด | `401 { message: "Unauthorized!" }` |
| ไม่มี token | `403 { message: "No token provided!" }` |

ดังนั้นใน `ApiClient` ให้มี helper ที่ตรวจ `data is Map && data['result'] == false` แล้ว throw `ApiException(message)` แม้ status จะเป็น 200

---

## 4. Authentication & Session

พฤติกรรม server (จาก `backend/controllers/auth.controller.js`):

- `POST /auth/login` `{ Username, Password }` → `accessToken` (JWT อายุ **15 นาที**) + ตั้ง cookie `refreshToken` (HttpOnly, อายุ **1 ชม.**, `sameSite: Strict`, `secure` เฉพาะ production)
- `POST /auth/refresh` (ไม่มี body) → อ่าน cookie → ออก accessToken ใหม่ + **หมุน** refresh cookie ใหม่ (sliding 1 ชม.)
- `GET /auth/restorelogin` → `employeeData` (ใช้ตอนเปิดแอปเพื่อเช็ค session)
- `POST /auth/logout`, `GET /auth/sessions`, `DELETE /auth/sessions/:tokenId` (จัดการอุปกรณ์ที่ล็อกอิน)
- `POST /auth/change-password` body คือ **`{ oldPassword, newPassword, confirmNewPassword }`** (camelCase — README เขียนผิดเป็น `OldPassword/NewPassword`)
- พนักงาน `EmployeeStatusID = 2` (ยกเลิก) login ไม่ได้
- Server เดา `DeviceName` จาก `User-Agent` → ให้ส่ง UA เช่น `HondaNTP-Mobile (Android 14)` / `(iOS 18)` เพื่อให้หน้าจัดการอุปกรณ์อ่านรู้เรื่อง

### สิ่งที่ Flutter ต้องทำ

1. Dio + `CookieManager(PersistCookieJar(...))` เพื่อเก็บ/ส่ง `refreshToken` อัตโนมัติ (Dio ไม่เก็บ cookie เอง)
2. เก็บ `accessToken` ใน `flutter_secure_storage`
3. `QueuedInterceptor` (ทำแบบเดียวกับ `frontend/src/services/httpClient.js`):
   - ใส่ `x-access-token` ทุก request
   - เจอ `401` และ request นั้นไม่ใช่ `/auth/refresh` → เรียก refresh ครั้งเดียว (request อื่นที่ 401 พร้อมกันรอคิว) → retry
   - refresh ล้มเหลว → ล้าง token + cookie → ไปหน้า login พร้อมข้อความ "เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่"
   - เจอ `403` → logout
4. เปิดแอป: มี token → `GET /auth/restorelogin`; ถ้า 401 ให้ interceptor ลอง refresh ก่อน
5. ⚠️ Production ใช้ cookie `secure` → server ต้องเป็น **HTTPS** ไม่งั้น cookie จะไม่ถูกส่ง

### สิทธิ์ (จาก `employeeData`)

`employeeData` มี `PositionID`, `RoleID`, `position`, `role`, `employeeStatus`, `ProfileImage`

| PositionID | ตำแหน่ง |
| --- | --- |
| 1 | ผู้ดูแลระบบ |
| 2 | ผู้จัดการ |
| 3 | พนักงานบัญชี |
| 4 | พนักงานรับรถ |
| 5 | พนักงานช่าง |

กฎที่มีในเว็บ: ปุ่ม "ลบรายการขาย" แสดงเฉพาะ `PositionID` 1 หรือ 2 — ให้ทำ helper `bool canManage(Employee e) => [1, 2].contains(e.positionId);`
(หมายเหตุ: `AGENT.md` เขียนว่า 1=Manager, 2=Admin สลับกับ seed data แต่ผลเหมือนกันคืออนุญาตทั้ง 1 และ 2)

---

## 5. Lookup / Status Codes

ค่าคงที่จาก `backend/seeders/data/*.json` — ทำเป็น enum/const ใน `lib/core/constants/`

**WorkStatus (สถานะงานซ่อม)**

| ID | en | th |
| --- | --- | --- |
| 1 | CHECKING | กำลังตรวจสอบรถ |
| 2 | CHECKED | ตรวจสอบรถแล้ว |
| 3 | INVOICE | สร้างใบแจ้งหนี้ |
| 4 | ALLOCATING | รอจัดสรรอุปกรณ์ |
| 5 | REPAIRING | อยู่ระหว่างซ่อม |
| 6 | REPAIRED | ซ่อมเสร็จแล้ว |
| 7 | SUCCESS | เสร็จสิ้น |
| 8 | PREPAIRING | อยู่ระหว่างการจัดซื้ออุปกรณ์ |
| 9 | REPAIRING - ALLOCATE MORE | อยู่ระหว่างซ่อม (จัดสรรอุปกรณ์เพิ่มเติม) |
| 99 | CANCEL | ยกเลิกการซ่อม |

**InvoiceStatus:** 1 รอยืนยันใบแจ้งหนี้ · 2 รอชำระเงิน · 3 ชำระเงินแล้ว · 99 ยกเลิก
**RecieptStatus:** 1 PAID · 2 VOID
**PartStatus:** 1 LOCKED ล็อค · 2 USED ใช้งานแล้ว · 3 PREPARING อยู่ระหว่างจัดซื้อ
**SaleStatus:** 1 PENDING รอชำระ · 2 PAID ชำระแล้ว
**AppointmentStatus:** 1 นัดหมาย (info) · 2 ดำเนินการแล้ว (success) · 99 ยกเลิก (error)
**EmployeeStatus:** 1 ปกติ · 2 ยกเลิกผู้ใช้งาน
**Role:** 1 SuperAdministrator · 2 Administrator · 3 User
**VatType:** 0 = รวม VAT ในราคา (include) · 1 = แยก VAT (exclude); อัตรา 7%

Lookup อื่นที่ต้องโหลดจาก API (cache ไว้ใน `LookupProvider` ตอน login): `customerTitle`, `addressType`, `brands`, `carModel`, `province`, `unit`, `partCategory`, `repairCategory`, `imageCarType`, `vendorType`, `discounttype`, `position`, `role`

---

## 6. Data Models

ชื่อ field ใช้ **PascalCase ตาม backend** (เช่น `CustomerID`, `PartName_th`) ใน `fromJson`/`toJson` แต่ใน Dart ใช้ camelCase ปกติ ID ส่วนใหญ่เป็น `int` ยกเว้นตามตาราง

| Model | Fields หลัก | หมายเหตุ |
| --- | --- | --- |
| Employee | EmployeeID, Username, FirstName, LastName, PositionID, RoleID, EmployeeStatusID, EmployeeEmail, EmployeeTel, ProfileImage | |
| Customer | CustomerID, CustomerTitleID, CustomerName, CustomerSurname, IDNumber, CustomerTel, RatingColor | มีหลาย Address |
| Address | AddressID, OwnerID, AddressTypeID, Line1, Line2, SubDistrictID, DistrictID, ProvinceID, IsDefault | `Zipcode` อยู่ที่ SubDistrict |
| Car | CarID, CustomerID, BrandID, ModelID, CarTitle, CarNumber, ProvinceID, VIN, EC, Color | ทะเบียน = CarTitle + CarNumber + จังหวัด |
| Quotation | **QuotationID (String `QT-…`)**, QuotationDate, isVat, VatType, BrandID, ModelID, CarID, Mileage, GasInstalation, TireType, TaxDate, Comment, EmployeeID, CustomerID, AddressID | |
| QuotationDetail | QuotationDetailID, QuotationID, RepairCategoryID, PresetID, CopiedToQuotationID | ค่าแรง/หมวดงาน |
| QuotationPart | QuotationPartID, QuotationDetailID, PartID, NumOfUse, PricePerUnit, ServiceFee | |
| CashPledge | CashPledgeID, QuotationID, PledgeTitle, PledgeAmount | มัดจำ |
| Repair | RepairID, BrandID, ModelID, CarID, CustomerID, WorkStatusID, RepairDate, EmployeeID, QuotationID, ReceiveType, ReceiveAppointmentDate | |
| RepairDetail | RepairDetailID, RepairID, RepairCategoryID, PresetID, FollowUpStatus, FollowUpRemark, FollowUpDate | |
| RepairPart | RepairPartID, RepairDetailID, PartID, NumOfUse, PricePerUnit, ServiceFee, Discount, isDiscount, PartStatusID, AllocatedNum | |
| Invoice | **InvoiceID (String `INV-…`)**, RepairID, QuotationID, IsDeposit, isVat, VatType, InvoiceDate, InvoiceStatusID, EmployeeID, Amount | `Amount` = Net Total หลังยืนยัน |
| ManualInvoice | **ManualInvoiceID (String `INVM-…`)**, CarID, CustomerID, AddressID, IsDeposit, isVat, VatType, InvoiceDate, InvoiceStatusID, EmployeeID, Amount, Comment | |
| Receipt | BillingID, RepairID, InvoiceID, RecieptStatusID, EmployeeID, Amount, IsDeposit | |
| Part | PartID, PartNumber, PartName_en, PartName_th, PartAmount (stock), PricePerUnit, UnitID, ServiceFee | |
| RecievePart | RecievePartID, RecieveNumber, EmployeeID, isVat, VatType, vat, RecieveDate, Amount, VendorID, Status, filename | ซื้อเข้า (multipart) |
| SalePart | SalePartID, EmployeeID, isVat, VatType, SaleDate, VendorID, AddressID, SaleStatusID, NumOfDiscount, Amount, DiscountTypeID | ขายหน้าร้าน |
| Vendor | VendorID, VendorName, VendorTypeID, IDNumber, VendorTel, RatingColor | |
| Preset / PresetDetail | PresetID, Preset, Status / PresetID, PartID, NumOfUse | ชุดงานซ่อมมาตรฐาน |
| Appointment | AppointmentID, AppointmentDate, Subject, CarID, QuotationID, CustomerID, AppointmentStatusID, EmployeeID, ContactName, ContactPhone, CarDetails, CarTitle, CarNumber, ProvinceID, Notes | |
| AppointmentRequest | RequestID, CarID, CarTitle, CarNumber, ProvinceID, CarDetails, CustomerName, CustomerTel, Symptoms, AppointmentDate, IsApproved, EmployeeID | |
| FollowUpConfig | ConfigID, RepairCategoryID, PresetID, FollowUpDays, Description | |
| ImageCar | ImageCarID, FileName, ImageCarTypeID, QuotationID | ผูกกับ **Quotation** ไม่ใช่ Repair |

> ⚠️ ชื่อสะกดตาม DB: `Recieve`, `Reciept`, `GasInstalation` — ต้องใช้ตามนี้ใน JSON key
> ⚠️ ตัวเลขเงินจาก MySQL DOUBLE/DECIMAL อาจมาเป็น `String` หรือ `num` — parse ด้วย helper `toDouble(dynamic v)` เสมอ
> ใช้ `mobile/lib/models/repair_model.dart` ใน repo เดิมเป็นตัวอย่างโครงสร้าง nested include ได้

---

## 7. API Endpoints (จากโค้ดจริง)

Path ไม่สนตัวพิมพ์เล็ก/ใหญ่ (Express default) แต่ให้เขียนตามนี้ CRUD มาตรฐาน = `POST /`, `GET /`, `GET /:id`, `PUT /:id`, `DELETE /:id`

**Auth** `/auth` — `login`, `refresh`, `logout`, `restorelogin`, `change-password`, `register`, `GET sessions`, `DELETE sessions/:tokenId`

**ลูกค้า / ที่อยู่**
- `/customers` CRUD, `POST /customers/simple`, `GET /customers/check-id-number/:id`
- `/addresses` CRUD, `PUT /addresses/change-default-address/:id`
- `/province` · `GET /district/province/:provinceId` · `GET /subDistrict/district/:districtId` (Cascading dropdown → ได้ `Zipcode`)
- `/customerTitle`, `/addressType`

**รถ**
- `/cars` CRUD, `GET /cars/by-customer/:customerId`, `GET /cars/by-model/:modelId`, `POST /cars/with-customer`, `POST /cars/check-existence`
- `/brands` · `/carModel`, `GET /carModel/brand/:brandId`

**ใบเสนอราคา**
- `/quotation` CRUD, `GET /quotation/logs/:id`, `POST /quotation/copy`
- `/quotation-detail` CRUD, `POST /quotation-detail/create-with-parts` `{ QuotationID, RepairCategoryID, PresetID, quotationParts: [{ PartID, NumOfUse }] }`, `GET /quotation-detail/by-quotation-id/:id`, `DELETE /quotation-detail/delete-with-parts/:id`
- `/quotation-part` CRUD
- `/cash-pledge` `POST`, `GET /cash-pledge/by-quotation-id/:id`, `DELETE /:id`

**งานซ่อม**
- `/repair` CRUD, `GET /repair/by-workStatusId/:id`, `GET /repair/by-car/:carId`, `GET /repair/logs/:id` (timeline), `GET /repair/history/:carId/:presetId`, `POST /repair/cancel/:id`
- ช่าง: `GET /repair/get-attendees/:id`, `PUT /repair/set-attendees/:id` `{ attendees: [EmployeeID] }`, `DELETE /repair/remove-attendees/:id`
- `/repairDetail` CRUD, `GET /repairDetail/by-repair-id/:id`, `POST /repairDetail/with-part`, `DELETE /repairDetail/delete-with-parts/:id`
- `/repairPart` CRUD, `PUT /repairPart/bulk/update` `{ updates: [{ RepairPartID, NumOfUse, Discount, isDiscount, ServiceFee, PartStatusID }] }`, `DELETE /repairPart/bulk/delete`

**การเงิน**
- `/invoices` CRUD, `POST /invoices/create-with-repair` `{ QuotationID, BrandID, ModelID, CustomerID, CarID }`, `GET /invoices/by-repair-id/:id`, `GET /invoices/by-quotation-id/:id`
- `/manual-invoices` CRUD, `GET /manual-invoices/logs/:id`
- `/receipts` `GET`, `GET /:id`, `POST` `{ InvoiceID, RepairID, Amount }`, `PUT /receipts/:id/cancel`, `GET /receipts/by-repair-id/:id`, `GET /receipts/by-quotation-id/:id`

**คลัง / ซื้อขาย**
- `/parts` CRUD
- `/recievePart` CRUD — POST เป็น `multipart/form-data` `{ file, data: <JSON string> }`
- `/salePart` `POST`, `GET`, `GET /:id`, `DELETE /:id`, `GET /:id/receipt`, `GET /:id/delivery-note`
- `/vendors` CRUD, `/vendorType`
- `/preset` CRUD, `/presetDetails` CRUD + `POST /bulk`
- `/repairCategory` CRUD, `POST /repairCategory/create-with-ref`
- `/refModelCategoryParts` CRUD + `POST /bulk`

**นัดหมาย / ติดตาม**
- `/appointments` CRUD, `GET /appointments/statuses`
- `/appointmentRequests` CRUD
- `/follow-ups` — `GET/POST /configs`, `PUT/DELETE /configs/:id`, `GET /tracking`, `PUT /tracking/:id`

**รายงาน**
- `/dashboard` — `GET /overview`, `GET /details/repairs`, `GET /details/revenue`, `GET /details/expenses`
- `/work-summary` — `GET /?year=2024` (ค.ศ.), `GET /years`

**พนักงาน**
- `/employee` `GET`, `GET /:id`, `PUT /:id`, `DELETE /:id`, `PUT /:id/reset-password`, `POST /employee/profile/upload` (multipart)

**รูปภาพ & PDF**
- อัปโหลดรูปรถ: `POST /imageCar` (multipart), `GET /imageCar/quotationID/:quotationId`, `DELETE /imageCar/:id`
- แสดงรูป: `GET /images/car/:quotationId/:filename`, `GET /images/profile/:filename`
- ไฟล์ใบเสร็จซื้อเข้า: `GET /uploads/recievePart/<filename>` (static)
- PDF (`GET`, ใช้ `?token=`): `/pdf/create-quotation/:id`, `/pdf/create-quotation-group/:id`, `/pdf/create-invoice/:id`, `/pdf/create-deposit-invoice/:id`, `/pdf/create-manual-invoice/:id`, `/pdf/create-receipt/:id`, `/pdf/create-deposit-receipt/:id`, `/pdf/create-manual-receipt/:id`; ใบเสร็จ/ใบส่งของการขายใช้ `/salePart/:id/receipt`, `/salePart/:id/delivery-note`

> ก่อน implement endpoint ที่เป็น multipart (`imageCar`, `recievePart`, `employee/profile/upload`) ให้เปิด middleware/controller ใน backend ดูชื่อ field ของไฟล์และ body ให้แน่ชัด

---

## 8. Business Logic ที่ต้องทำให้ตรงกับเว็บ

### การคำนวณเงิน (Invoice / Quotation / Receipt)

```
lineTotal   = NumOfUse × PricePerUnit + ServiceFee − (isDiscount ? Discount : 0)
Subtotal    = Σ lineTotal                     // รวมเป็นเงิน
VAT         = isVat ? (VatType == 1 ? Subtotal × 0.07 : Subtotal × 7/107) : 0
GrandTotal  = VatType == 1 ? Subtotal + VAT : Subtotal   // รวมจำนวนเงิน
NetTotal    = GrandTotal − Σ CashPledge.PledgeAmount      // ยอดที่ต้องชำระ / ยอดรวมสุทธิ
```

- ยืนยัน Invoice (`PUT /invoices/:id` `{ InvoiceStatusID: 2, isVat, Amount: NetTotal }`) → server เก็บ `Amount`
- ใบเสร็จผูกกับ Receipt ที่ `RecieptStatusID = 1` เท่านั้น
- ถ้า Quotation มีใบเสร็จ PAID แล้ว → **ห้ามลบรายการอะไหล่หรือเงินมัดจำ** ของ Quotation นั้น (ซ่อนปุ่มใน UI ด้วย)
- ⚠️ สูตร line total / การคิด ServiceFee และ VAT แบบ include ให้ตรวจกับ `frontend/src/pages/system/invoices/details/[invoiceID].vue` และ `backend/controllers/pdfCreateInvoice.controller.js` ก่อน — ยอดในแอปต้องตรงกับ PDF ทุกสตางค์ ทำเป็น pure function + unit test

### Stock
- รับอะไหล่เข้า (RecievePart) → server เพิ่ม `Parts.PartAmount`; ลบ → ตัด stock (ต้องมีพอ)
- ตรวจเลขที่ใบเสร็จซ้ำก่อนบันทึก
- เพิ่มอะไหล่เข้างานซ่อม → แสดง stock และกันกรอกเกินในฝั่งแอป

### Work Summary
- 1 งานซ่อม = 1 คะแนน หารเท่ากันตามจำนวนช่างใน `RepairAttendance`
- API รับ/ส่งปี ค.ศ. → **แสดงเป็น พ.ศ. (+543)**

### Localization / UX
- ข้อความแจ้งเตือนมาตรฐาน: "สำเร็จ!", "เกิดข้อผิดพลาด!", "ยืนยันการทำรายการ?", "แจ้งเตือน!"; ปุ่ม "ยืนยัน" (น้ำเงิน) / "ยกเลิก" (แดง)
- ทำ `AppDialogs.success/error/confirm` กลางที่เดียว
- ลิสต์ใหญ่ (repairs, customers, cars, parts) แบ่งหน้า 20 รายการ + ค้นหา (ลูกค้าค้นจากทะเบียนรถ/จังหวัดได้)
- ทุก list endpoint ส่งทั้งหมดมาครั้งเดียว (ไม่มี server pagination) → ทำ paginate/filter ฝั่ง client

---

## 9. README vs โค้ดจริง

| README เขียน | โค้ดจริง |
| --- | --- |
| `/district/by-province-id/:id`, `/district/province/:ProvinceID` | `/district/province/:id` |
| `/subdistrict/by-district-id/:id` | `/subDistrict/district/:id` |
| `/cars/by-customer-id/:id` | `/cars/by-customer/:id` |
| `/carmodel/by-brand-id/:BrandID` | `/carModel/brand/:id` |
| `/repairpart/bulk-update` | `/repairPart/bulk/update` |
| `/imagecar/repairID/:RepairID`, FormData มี `RepairID` | `/imageCar/quotationID/:id` — รูปผูกกับ QuotationID |
| `/presetdetails` | `/presetDetails` |
| `change-password { OldPassword, NewPassword }` | `{ oldPassword, newPassword, confirmNewPassword }` |
| `/pdf/create-sale-receipt/:billingId` | `/salePart/:id/receipt` (ไม่มี route นี้ใน `pdf.routes`) |

---

## 10. หน้าจอ & ลำดับการพัฒนา

เมนูตามเว็บ (`frontend/src/layouts/full/vertical-sidebar/sidebarItem.js`) แบ่ง phase ตามความคุ้มค่าบนมือถือ — งานหน้างาน (รับรถ, ช่าง, ถ่ายรูป) มาก่อน งานบัญชี/ตั้งค่าที่ตารางเยอะไว้ทีหลัง

| Phase | หน้า | Route | อ้างอิงเว็บ |
| --- | --- | --- | --- |
| **0 Foundation** | Splash/restore session, Login, Shell (Drawer + BottomNav), ApiClient, Auth, Lookups, Theme K2D, Dialog กลาง | `/login`, `/` | `login.vue` |
| **1 หน้างาน** | ซ่อมรถยนต์ — list ตาม WorkStatus (tab/filter) | `/repairs` | `system/repairs/index.vue` |
| | รายละเอียดงานซ่อม + Timeline + เปลี่ยนสถานะ + บันทึกช่าง | `/repairs/:id` | `repairs/details/[repairID].vue` |
| | แก้ไขงานซ่อม: เพิ่มจาก Preset, เพิ่ม/แก้/ลบอะไหล่ (bulk update) | `/repairs/:id/edit` | `repairs/[repairID].vue` |
| | รูปรถ: ถ่าย/เลือก, gallery, ลบ, ดูเต็มจอ | ใน quotation/repair | `components/cars` |
| | จัดสรรอุปกรณ์ (status 4/9, PartStatus, AllocatedNum) | `/monitoring` | `system/monitoring/index.vue` |
| **2 ข้อมูลหลัก** | ลูกค้า + ที่อยู่ (cascading) | `/customers` | `system/customers/index.vue` |
| | รถยนต์ (+ ประวัติซ่อม `/repair/by-car`) | `/cars` | `system/cars/index.vue` |
| | นัดหมาย: ปฏิทิน, list, คำขอนัด (approve), สร้าง/แก้ | `/appointments` | `dashboards/appointments/*` |
| | ติดตามรอบซ่อม | `/follow-ups` | `dashboards/follow-ups/index.vue` |
| **3 เอกสาร** | ใบเสนอราคา list/detail + เพิ่มรายการ + มัดจำ + PDF + อนุมัติ → create-with-repair | `/quotations`, `/quotations/:id` | `system/quotation/*` |
| | ใบแจ้งหนี้ list/detail + ยืนยัน + PDF | `/invoices`, `/invoices/:id` | `system/invoices/*` |
| | ใบแจ้งหนี้ manual | `/manual-invoices` | `system/manual-invoices/*` |
| | ใบเสร็จ list/detail + ยกเลิก + PDF | `/receipts`, `/receipts/:id` | `system/reciept/*` |
| **4 คลัง** | สินค้าคงคลัง (ค้นหา, ดู stock) | `/stock` | `system/stock/index.vue` |
| | ซื้อขายอะไหล่ (tab ซื้อเข้า/ขาย, แนบไฟล์, VAT) | `/trading` | `system/trading/index.vue` |
| | คู่ค้า + ที่อยู่ | `/vendors` | `system/vendors/index.vue` |
| **5 รายงาน/ตั้งค่า** | Dashboard overview (KPI cards drill-down, Top 5 กราฟ) | `/dashboard` | `dashboards/overview/index.vue` |
| | สรุปการทำงาน (เลือกปี พ.ศ.) | `/work-summary` | `system/work-summary/index.vue` |
| | พนักงาน (+ reset password, รูปโปรไฟล์) | `/employees` | `system/employees/index.vue` |
| | Preset, จัดกลุ่มอะไหล่กับรถ (ref) | `/preset`, `/ref` | `system/preset`, `system/ref` |
| | บัญชีผู้ใช้: เปลี่ยนรหัส, อุปกรณ์ที่ล็อกอิน (revoke) | `/account` | `account-settings/index.vue` |

เวลาทำแต่ละหน้า: เปิดไฟล์ `.vue` ที่อ้างอิงใน repo ต้นทาง ดูว่าเรียก API อะไร ส่ง payload อะไร และ validation อะไร แล้วทำให้ตรงกัน

---

## 11. โครงสร้างโฟลเดอร์

```
lib/
  main.dart
  app.dart                      # MaterialApp.router, theme, locale th
  core/
    config/env.dart             # API_BASE_URL จาก --dart-define
    network/api_client.dart     # Dio + cookie jar + auth interceptor + result:false handling
    network/api_exception.dart
    storage/token_storage.dart  # flutter_secure_storage
    constants/statuses.dart     # WorkStatus, InvoiceStatus, ... (ข้อ 5)
    utils/money.dart            # format เงิน, toDouble
    utils/thai_date.dart        # วันที่ไทย / พ.ศ.
    utils/finance.dart          # สูตรข้อ 8 (pure + tested)
    widgets/                    # AppDialogs, StatusChip, PagedListView, SearchField, CascadingAddressFields
  router/app_router.dart        # go_router + redirect ตาม AuthProvider
  layouts/main_layout.dart
  features/
    auth/        (data/ models/ providers/ pages/)
    repairs/
    customers/
    cars/
    appointments/
    follow_ups/
    quotations/
    invoices/
    receipts/
    stock/
    trading/
    vendors/
    dashboard/
    work_summary/
    employees/
    settings/    (preset, ref, account)
test/
  finance_test.dart
```

แต่ละ feature: `data/<feature>_api.dart` (เรียก `ApiClient`), `models/`, `pages/`, `widgets/`

---

## 12. Code Conventions

- ตอบ/สื่อสารภาษาไทย, comment ในโค้ดภาษาอังกฤษ (ตาม `AGENT.md`)
- `flutter_lints` + ใช้ `{}` กับ if เสมอ, ไม่ใส่ `.toList()` เกินจำเป็นใน spread
- ฟอร์มใช้ `Form` + `GlobalKey<FormState>`
- async/await + try/catch ทุกจุดที่เรียก API แสดงผ่าน `AppDialogs.error`
- ไม่ hardcode URL/secret; ไม่ log password/token (ปิด `LogInterceptor` body ใน release)
- ทุกหน้ารองรับ loading / empty / error state และ pull-to-refresh

---

## 13. เรื่องที่ควรแจ้งทีม Backend (เจอระหว่างอ่าน repo)

ไม่ใช่งาน Flutter โดยตรง แต่กระทบความปลอดภัยของแอป:

1. **`backend/.env` และ `frontend/.env` ถูก commit ขึ้น repo** (มี `JWT_SECRET`, `DB_PASSWORD`) — ควรเปลี่ยน secret และเอาออกจาก git
2. **`/auth/register` ใช้รหัสผ่านคงที่ `"password"`** (`const Password = "password"` ใน `auth.controller.js`) ไม่ได้ใช้ค่าที่ส่งมา
3. **Route `/appointments`, `/appointmentRequests`, `/dashboard` ไม่มี `checkJwt`** — เรียกได้โดยไม่ล็อกอิน
4. ถ้า `JWT_ENABLED` ไม่ใช่ `'true'` ทุก request จะถูกมองเป็น EmployeeID 1 (admin)
5. Error ส่วนใหญ่ตอบ HTTP 200 + `result:false` ทำให้ client แยก error ยาก

---

## 14. หมายเหตุเรื่อง `mobile/` เดิมใน repo

- มีแค่ `main.dart`, `login_page.dart`, `main_layout.dart`, `placeholder_page.dart`, `api_service.dart`, `repair_model.dart`, `router.dart`
- `router.dart` import หน้า `pages/system/repairs/*`, `customers_page.dart`, `cars_page.dart`, `employees_page.dart` ที่ **ไม่มีอยู่ใน repo** → build ไม่ผ่านตามสภาพ แม้ `AGENT.md` จะบอกว่าทำแล้ว ~28%
- ใช้ได้เป็นตัวอย่าง: theme K2D, ShellRoute, model `Repair` แบบ nested, รายชื่อ method ใน `ApiService`
- `ApiService` เดิม **ไม่แนบ token และไม่มี refresh** → ห้ามลอกส่วน network มาใช้ตรงๆ ให้ทำตามข้อ 4

---

## 15. Definition of Done (ต่อหน้า)

- [ ] เรียก API ตาม endpoint จริง (ข้อ 7) และจัดการ `result:false`
- [ ] ยอดเงินตรงกับเว็บและ PDF (มี unit test สำหรับสูตร)
- [ ] สิทธิ์ตาม PositionID ถูกต้อง
- [ ] ข้อความไทยตามมาตรฐาน, วันที่ไทย, เงิน 2 ตำแหน่ง
- [ ] loading / empty / error / pull-to-refresh
- [ ] ทดสอบบน Android + iOS, token หมดอายุระหว่างใช้งานแล้ว refresh ต่อได้
- [ ] `flutter analyze` ไม่มี warning
