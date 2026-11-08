import 'package:flutter/material.dart';

import '../../data/models.dart';

enum NavGroup { main, admin }

class NavItem {
  const NavItem({
    required this.path,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.roles,
    this.group = NavGroup.main,
    this.mobileTab = false,
  });

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Set<Role> roles;
  final NavGroup group;

  /// Shown in the phone bottom bar (everything else lives under "More").
  final bool mobileTab;
}

const _all = {Role.worker, Role.manager, Role.admin};
const _mgr = {Role.manager, Role.admin};
const _admin = {Role.admin};

const navItems = <NavItem>[
  NavItem(path: '/dashboard', label: 'Dashboard', icon: Icons.space_dashboard_outlined, selectedIcon: Icons.space_dashboard_rounded, roles: _mgr, mobileTab: true),
  // Workers complete checks; managers and admins get a read-only overview + verification.
  NavItem(path: '/checks', label: 'My checks', icon: Icons.checklist_rounded, selectedIcon: Icons.checklist_rounded, roles: {Role.worker}, mobileTab: true),
  NavItem(path: '/checks', label: 'Checks', icon: Icons.fact_check_outlined, selectedIcon: Icons.fact_check_rounded, roles: _mgr, mobileTab: true),
  NavItem(path: '/scan', label: 'Scan', icon: Icons.qr_code_scanner_rounded, selectedIcon: Icons.qr_code_scanner_rounded, roles: _all, mobileTab: true),
  NavItem(path: '/equipment', label: 'Equipment', icon: Icons.precision_manufacturing_outlined, selectedIcon: Icons.precision_manufacturing_rounded, roles: _all, mobileTab: true),
  NavItem(path: '/findings', label: 'Findings', icon: Icons.report_problem_outlined, selectedIcon: Icons.report_problem_rounded, roles: _all),
  NavItem(path: '/history', label: 'History', icon: Icons.history_rounded, selectedIcon: Icons.history_rounded, roles: _all),
  NavItem(path: '/admin/check-sheets', label: 'Assignments', icon: Icons.assignment_ind_outlined, selectedIcon: Icons.assignment_ind_rounded, roles: _mgr, group: NavGroup.admin),
  NavItem(path: '/admin/equipment', label: 'Manage equipment', icon: Icons.inventory_2_outlined, selectedIcon: Icons.inventory_2_rounded, roles: _mgr, group: NavGroup.admin),
  NavItem(path: '/admin/users', label: 'Users', icon: Icons.group_outlined, selectedIcon: Icons.group_rounded, roles: _admin, group: NavGroup.admin),
  NavItem(path: '/admin/plants', label: 'Plants', icon: Icons.factory_outlined, selectedIcon: Icons.factory_rounded, roles: _admin, group: NavGroup.admin),
];

List<NavItem> itemsFor(Role role) => navItems.where((i) => i.roles.contains(role)).toList();

/// Phone bottom-bar tabs for a role: up to 4 primary tabs + "More".
List<NavItem> mobileTabsFor(Role role) {
  final tabs = itemsFor(role).where((i) => i.mobileTab).toList();
  // Workers have no dashboard: give History the free slot.
  if (tabs.length < 4) {
    tabs.addAll(itemsFor(role).where((i) => !i.mobileTab && i.group == NavGroup.main).take(4 - tabs.length));
  }
  return tabs.take(4).toList();
}

String homeFor(Role role) => role.isManagerOrAdmin ? '/dashboard' : '/checks';

bool isActivePath(String location, String path) => location == path || location.startsWith('$path/');
