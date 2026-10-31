import '../../core/constants/statuses.dart';
import '../../core/utils/json.dart';

/// Employee as returned by `/auth/login`, `/auth/restorelogin` and `/employee`.
class Employee {
  const Employee({
    required this.id,
    required this.username,
    required this.firstName,
    required this.lastName,
    this.positionId,
    this.positionTitle,
    this.roleId,
    this.roleName,
    this.employeeStatusId,
    this.employeeStatusTitle,
    this.email,
    this.tel,
    this.raw = const {},
  });

  factory Employee.fromJson(Map<String, dynamic> j) {
    final position = asMap(j['position'] ?? j['Position']);
    final role = asMap(j['role'] ?? j['Role']);
    final status = asMap(j['employeeStatus'] ?? j['EmployeeStatus']);
    return Employee(
      id: asInt(j['EmployeeID']) ?? 0,
      username: asString(j['Username']) ?? '',
      firstName: asString(j['FirstName']) ?? '',
      lastName: asString(j['LastName']) ?? '',
      positionId: asInt(j['PositionID']),
      positionTitle: asString(position?['PositionTitle']),
      roleId: asInt(j['RoleID']),
      roleName: asString(role?['RoleName']),
      employeeStatusId: asInt(j['EmployeeStatusID']),
      employeeStatusTitle: asString(status?['EmployeeStatusTitle']),
      email: asString(j['EmployeeEmail']),
      tel: asString(j['EmployeeTel']),
      raw: j,
    );
  }

  final int id;
  final String username;
  final String firstName;
  final String lastName;
  final int? positionId;
  final String? positionTitle;
  final int? roleId;
  final String? roleName;
  final int? employeeStatusId;
  final String? employeeStatusTitle;
  final String? email;
  final String? tel;
  final Map<String, dynamic> raw;

  String get fullName => '$firstName $lastName'.trim();

  String get initials {
    final f = firstName.isNotEmpty ? firstName[0] : '';
    final l = lastName.isNotEmpty ? lastName[0] : '';
    final s = '$f$l';
    return s.isEmpty ? '?' : s;
  }

  /// Admin or manager — allowed to delete records and confirm documents.
  bool get canManage =>
      positionId == Position.admin || positionId == Position.manager;
}
