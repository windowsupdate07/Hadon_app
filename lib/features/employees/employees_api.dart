import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../auth/employee.dart';

/// `EmployeeStatus` seed values.
class EmployeeStatusId {
  EmployeeStatusId._();

  static const active = 1;
  static const disabled = 2;
}

/// Password the backend assigns to every account created through
/// `POST /auth/register` (hard-coded in auth.controller.js).
const defaultEmployeePassword = 'password';

extension EmployeeSearch on Employee {
  bool matches(String q) {
    final s = q.toLowerCase();
    return fullName.toLowerCase().contains(s) ||
        username.toLowerCase().contains(s) ||
        (email ?? '').toLowerCase().contains(s) ||
        (tel ?? '').contains(s) ||
        (positionTitle ?? '').toLowerCase().contains(s) ||
        (roleName ?? '').toLowerCase().contains(s);
  }
}

class EmployeesApi {
  EmployeesApi(this._api);

  final ApiClient _api;

  /// The controller already excludes `Password`.
  Future<List<Employee>> findAll() =>
      _api.getList('/employee', Employee.fromJson);

  /// `PUT /employee/:id` is a generic `Model.update(req.body)`, so only the
  /// profile fields are sent — never `Password` or `Username`.
  Future<void> update(int id, EmployeeInput input) =>
      _api.put('/employee/$id', data: input.toJson());

  Future<void> remove(int id) => _api.delete('/employee/$id');

  /// `POST /auth/register`. The controller ignores any submitted password
  /// and hashes the constant [defaultEmployeePassword]. `Password` must NOT
  /// be sent: the controller spreads the remaining body over the hashed
  /// value, which would store a plain-text password and break login.
  Future<void> register(String username, EmployeeInput input) async {
    try {
      await _api.post(
        '/auth/register',
        data: {'Username': username, ...input.toJson()},
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
