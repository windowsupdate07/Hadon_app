import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/utils/json.dart';
import '../auth/employee.dart';

/// `EmployeeStatus` seed values.
class EmployeeStatusId {
  EmployeeStatusId._();

  static const active = 1;

  /// Setting this through `PUT /employee/:id` also revokes all of the
  /// employee's refresh tokens (logged out everywhere).
  static const disabled = 2;
}

/// `Role` seed values. Lower id = more privileges.
class RoleId {
  RoleId._();

  static const superAdmin = 1;
  static const admin = 2;
  static const user = 3;
}

/// Password the backend assigns on `POST /auth/register` and on
/// `PUT /employee/:id/reset-password` (both hard-coded on the server).
const defaultEmployeePassword = 'password';

/// Default avatars served from the backend's `assets/profile/` folder.
final defaultProfileImages = List<String>.unmodifiable([
  for (var i = 1; i <= 12; i++) 'user-$i.jpg',
]);

extension EmployeeExtras on Employee {
  bool matches(String q) {
    final s = q.toLowerCase();
    return fullName.toLowerCase().contains(s) ||
        username.toLowerCase().contains(s) ||
        (email ?? '').toLowerCase().contains(s) ||
        (tel ?? '').contains(s) ||
        (positionTitle ?? '').toLowerCase().contains(s) ||
        (roleName ?? '').toLowerCase().contains(s);
  }

  /// `Employee.ProfileImage` (file name under `/images/profile/`).
  String? get profileImage => asString(raw['ProfileImage']);

  bool get isDisabled => employeeStatusId == EmployeeStatusId.disabled;

  /// Web rule (EmployeeTable.vue): an account can only be edited by someone
  /// with a strictly higher role (smaller RoleID). This also means nobody
  /// edits their own record from this screen.
  bool canEditEmployee(Employee target) {
    final mine = roleId;
    final theirs = target.roleId;
    return mine != null && theirs != null && theirs > mine;
  }

  /// The web only offers roles below the signed-in user's role when
  /// creating, so a plain "User" cannot create accounts.
  bool get canCreateEmployee {
    final mine = roleId;
    return mine != null && mine < RoleId.user;
  }

  /// Deleting is mobile-only (the web has no delete); require both the role
  /// hierarchy and an admin/manager position.
  bool canDeleteEmployee(Employee target) =>
      canManage && canEditEmployee(target);

  /// Own photo (web: account settings) or someone the user may edit.
  bool canChangePhotoOf(Employee target) =>
      id == target.id || canEditEmployee(target);
}

class EmployeesApi {
  EmployeesApi(this._api);

  final ApiClient _api;

  /// `GET /employee` — excludes `Password`, includes `employeeStatus`,
  /// `position` and `role`.
  Future<List<Employee>> findAll() =>
      _api.getList('/employee', Employee.fromJson);

  /// `PUT /employee/:id` is `Employee.update(req.body)`, so only the
  /// profile fields are sent — never `Password` or `Username`.
  Future<void> update(int id, EmployeeInput input) =>
      _api.put('/employee/$id', data: input.toJson());

  /// `PUT /employee/:id` with only `ProfileImage`.
  Future<void> setProfileImage(int id, String filename) =>
      _api.put('/employee/$id', data: {'ProfileImage': filename});

  /// `PUT /employee/:id/reset-password` sets the password to
  /// [defaultEmployeePassword].
  Future<void> resetPassword(int id) =>
      _api.put('/employee/$id/reset-password');

  /// `DELETE /employee/:id` (crud.remove, soft delete).
  Future<void> remove(int id) => _api.delete('/employee/$id');

  /// `POST /employee/profile/upload` (multer field `image`). The server
  /// names the file after the `Username` form field, which must be sent
  /// before the file. Returns the stored file name; it still has to be saved
  /// with [setProfileImage].
  Future<String> uploadProfileImage(String username, String filePath) async {
    final form = FormData();
    form.fields.add(MapEntry('Username', username));
    form.files.add(
      MapEntry(
        'image',
        await MultipartFile.fromFile(filePath, filename: '$username.jpg'),
      ),
    );
    final res = await _api.postMultipart('/employee/profile/upload', form);
    final filename = res is Map ? asString(res['filename']) : null;
    if (filename == null) {
      throw const ApiException('อัปโหลดรูปภาพไม่สำเร็จ');
    }
    return filename;
  }

  /// `POST /auth/register`. The controller ignores any submitted password
  /// and hashes the constant [defaultEmployeePassword]. `Password` must NOT
  /// be sent: the controller spreads the remaining body over the hashed
  /// value, which would store a plain-text password and break login.
  Future<void> register(
    String username,
    EmployeeInput input, {
    String? profileImage,
  }) async {
    try {
      await _api.post(
        '/auth/register',
        data: {
          'Username': username,
          ...input.toJson(),
          'ProfileImage': ?profileImage,
        },
      );
    } on ApiException catch (e) {
      if (e.message == 'Failed! Username is already in use!') {
        throw ApiException(
          'ชื่อผู้ใช้งานนี้ถูกใช้แล้ว',
          statusCode: e.statusCode,
        );
      }
      rethrow;
    }
  }
}

/// Editable employee fields.
class EmployeeInput {
  const EmployeeInput({
    required this.firstName,
    required this.lastName,
    required this.positionId,
    required this.roleId,
    required this.statusId,
    this.email,
    this.tel,
  });

  final String firstName;
  final String lastName;
  final int positionId;
  final int roleId;
  final int statusId;
  final String? email;
  final String? tel;

  Map<String, dynamic> toJson() => {
    'FirstName': firstName,
    'LastName': lastName,
    'PositionID': positionId,
    'RoleID': roleId,
    'EmployeeStatusID': statusId,
    'EmployeeEmail': email,
    'EmployeeTel': tel,
  };
}
