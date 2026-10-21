// lib/widgets/admin_shell.dart
// Layout principal del panel web: AdminTopBar + navegación lateral + contenido.
// Responsive: amplio (nav fija expandida) / medio (solo iconos) / compacto (drawer).
// Spec: web-admin-corporativo — Tasks 4.1, 6.3

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/admin_design.dart';
import '../core/constants.dart';
import '../core/theme/app_colors.dart';
import '../services/auth_service.dart';
import 'admin_top_bar.dart';

// ── Ítem de navegación lateral ────────────────────────────────────
class AdminNavItem {
  final IconData icon;
  final String   label;
  final String   route;
  const AdminNavItem({
    required this.icon,
    required this.label,
    required this.route,
  });
}

// ── Ítems del menú admin ──────────────────────────────────────────
const List<AdminNavItem> _kAdminNavItems = [
  AdminNavItem(
    icon:  Icons.dashboard_outlined,
    label: 'Panel',
    route: AppConstants.routeAdmin,
  ),
];

// ── AdminShell ────────────────────────────────────────────────────
class AdminShell extends StatelessWidget {
  final Widget body;
  final String activeRoute;

  const AdminShell({
    super.key,
    required this.body,
    this.activeRoute = AppConstants.routeAdmin,
  });

  @override
  Widget build(BuildContext context) {
    final width     = MediaQuery.of(context).size.width;
    final isCompact = width < AdminDesign.breakpointCompact;
    final isWide    = width >= AdminDesign.breakpointMedium;

    final topBar = AdminTopBar(
      onLogout: () async {
        await AuthService().signOut();
        if (context.mounted) context.go(AppConstants.routeLogin);
      },
    );

    if (isCompact) {
      return Scaffold(
        appBar: topBar,
        drawer: _SideNav(
          items:       _kAdminNavItems,
          activeRoute: activeRoute,
          expanded:    true,
        ),
        body: _ContentArea(body: body),
      );
    }

    return Scaffold(
      appBar: topBar,
      body: Row(children: [
        _SideNav(
          items:       _kAdminNavItems,
          activeRoute: activeRoute,
          expanded:    isWide,
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _ContentArea(body: body)),
      ]),
    );
  }
}

// ── Área de contenido centrada con ancho máximo ───────────────────
class _ContentArea extends StatelessWidget {
  final Widget body;
  const _ContentArea({required this.body});

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
              maxWidth: AdminDesign.contentMaxWidth),
          child: body,
        ),
      ),
    );
  }
}

// ── Navegación lateral ────────────────────────────────────────────
class _SideNav extends StatelessWidget {
  final List<AdminNavItem> items;
  final String activeRoute;
  final bool   expanded;

  const _SideNav({
    required this.items,
    required this.activeRoute,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    final width = expanded
        ? AdminDesign.sideNavWidthExpanded
        : AdminDesign.sideNavWidthCollapsed;

    return SizedBox(
      width:  width,
      height: double.infinity,
      child: Material(
        color: AppColors.surface,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AdminDesign.s2),
          children: items.map((item) {
            final isActive = item.route == activeRoute;
            return _NavTile(
              item:     item,
              isActive: isActive,
              expanded: expanded,
              onTap:    () => context.go(item.route),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final AdminNavItem item;
  final bool isActive;
  final bool expanded;
  final VoidCallback onTap;

  const _NavTile({
    required this.item,
    required this.isActive,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.accent : AppColors.textSecondary;
    final bg    = isActive
        ? AppColors.accentSoft
        : Colors.transparent;

    return Semantics(
      selected: isActive,
      label: item.label,
      child: Tooltip(
        message: expanded ? '' : item.label,
        child: InkWell(
          onTap: onTap,
          focusColor: AppColors.accentSoft,
          hoverColor: AppColors.surfaceTint,
          child: Container(
            height:  48,
            margin:  const EdgeInsets.symmetric(
                horizontal: AdminDesign.s1, vertical: 2),
            decoration: BoxDecoration(
              color:        bg,
              borderRadius: BorderRadius.circular(AdminDesign.radiusCard),
            ),
            child: Row(children: [
              // Indicador activo
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width:  isActive ? 3 : 0,
                height: 24,
                margin: const EdgeInsets.only(right: AdminDesign.s1),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Icon(item.icon, color: color, size: 20),
              if (expanded) ...[
                const SizedBox(width: AdminDesign.s1),
                Expanded(
                  child: Text(
                    item.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isActive
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: color,
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
