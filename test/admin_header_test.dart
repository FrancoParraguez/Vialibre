// test/admin_header_test.dart
// Pruebas unitarias para formatCorporateDate, iniciales y respaldo de institución.
// Spec: web-admin-corporativo — Task 2.6

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:via_libre/core/corporate_date_formatter.dart';
import 'package:via_libre/models/admin_header_info.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_CL');
  });

  // ── formatCorporateDate ───────────────────────────────────────
  group('formatCorporateDate', () {
    test('lunes 19 oct 2026', () {
      final d = DateTime(2026, 10, 19);
      expect(formatCorporateDate(d), 'Lunes, 19 de octubre de 2026');
    });

    test('martes 1 enero 2026', () {
      final d = DateTime(2026, 1, 1);
      expect(formatCorporateDate(d), 'Jueves, 1 de enero de 2026');
    });

    test('mes de diciembre', () {
      final d = DateTime(2026, 12, 25);
      expect(formatCorporateDate(d), contains('diciembre'));
    });

    test('año bisiesto 29 de febrero 2028', () {
      final d = DateTime(2028, 2, 29);
      expect(formatCorporateDate(d), contains('29 de febrero de 2028'));
    });

    test('primera letra mayúscula siempre', () {
      for (int day = 1; day <= 7; day++) {
        // semana del 19 al 25 oct 2026 cubre los 7 días
        final d = DateTime(2026, 10, 18 + day);
        final result = formatCorporateDate(d);
        expect(result[0], result[0].toUpperCase(),
            reason: '$result debe empezar en mayúscula');
      }
    });

    test('cambio de día — misma semana produce días distintos', () {
      final lun = formatCorporateDate(DateTime(2026, 10, 19));
      final mar = formatCorporateDate(DateTime(2026, 10, 20));
      expect(lun, isNot(equals(mar)));
      expect(lun, contains('Lunes'));
      expect(mar, contains('Martes'));
    });
  });

  // ── formatCorporateDateShort ──────────────────────────────────
  group('formatCorporateDateShort', () {
    test('formato abreviado 19 oct 2026', () {
      final d = DateTime(2026, 10, 19);
      final result = formatCorporateDateShort(d);
      expect(result, contains('oct'));
      expect(result, contains('2026'));
    });
  });

  // ── AdminHeaderInfo.iniciales ─────────────────────────────────
  group('AdminHeaderInfo — iniciales', () {
    test('nombre simple → inicial', () {
      const h = AdminHeaderInfo(nombre: 'Carlos', institucion: 'X');
      expect(h.iniciales, 'C');
    });

    test('nombre compuesto → 2 iniciales', () {
      const h = AdminHeaderInfo(nombre: 'María José', institucion: 'X');
      expect(h.iniciales, 'MJ');
    });

    test('nombre con múltiples palabras → primera y última', () {
      const h = AdminHeaderInfo(nombre: 'Juan Pablo García', institucion: 'X');
      expect(h.iniciales, 'JG');
    });

    test('nombre vacío → A', () {
      const h = AdminHeaderInfo(nombre: '', institucion: 'X');
      expect(h.iniciales, 'A');
    });

    test('nombre solo espacios → A', () {
      const h = AdminHeaderInfo(nombre: '   ', institucion: 'X');
      expect(h.iniciales, 'A');
    });

    test('iniciales siempre en mayúscula', () {
      const h = AdminHeaderInfo(nombre: 'ana belén', institucion: 'X');
      expect(h.iniciales, 'AB');
    });
  });

  // ── AdminHeaderInfo — institución ─────────────────────────────
  group('AdminHeaderInfo — institución', () {
    test('institución presente → se muestra tal cual', () {
      const h = AdminHeaderInfo(nombre: 'X', institucion: 'SAMU Valparaíso');
      expect(h.institucionLabel, 'SAMU Valparaíso');
      expect(h.sinInstitucion, isFalse);
    });

    test('institución vacía → texto de respaldo', () {
      const h = AdminHeaderInfo(nombre: 'X', institucion: '');
      expect(h.institucionLabel, 'Institución no registrada');
      expect(h.sinInstitucion, isTrue);
    });

    test('institución solo espacios → texto de respaldo', () {
      const h = AdminHeaderInfo(nombre: 'X', institucion: '   ');
      expect(h.institucionLabel, 'Institución no registrada');
      expect(h.sinInstitucion, isTrue);
    });
  });
}
