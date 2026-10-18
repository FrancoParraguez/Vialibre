// lib/widgets/emergency_dispatch_dialog.dart
// Modal/bottom-sheet de configuración de misión de emergencia.
// Permite seleccionar un destino (con autocompletado o toque en mapa)
// o activar el modo sin destino fijo (spec modo-emergencia-sin-destino).
//
// TASK-01 del spec task2.md.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../core/constants.dart';
import '../core/theme/app_colors.dart';
import '../services/place_search_service.dart';
import '../services/permission_service.dart';

/// Resultado del diálogo de despacho.
class DispatchResult {
  /// `true` si se eligió un destino fijo, `false` si es modo sin destino fijo.
  final bool hasFixedDestination;

  /// Coordenada del destino seleccionado (null si sin destino fijo).
  final LatLng? destination;

  /// Etiqueta legible del destino (ej. "Hospital Carlos Van Buren").
  final String? destinationLabel;

  DispatchResult({
    required this.hasFixedDestination,
    this.destination,
    this.destinationLabel,
  });
}

/// Callback que recibe el resultado del diálogo.
typedef OnDispatchConfirmed = void Function(DispatchResult result);

class EmergencyDispatchDialog extends StatefulWidget {
  /// Origen capturado al presionar "Activar Emergencia".
  final LatLng origin;

  /// Si las notificaciones están concedidas (para mostrar banner si no).
  final bool notificationsEnabled;

  const EmergencyDispatchDialog({
    super.key,
    required this.origin,
    this.notificationsEnabled = true,
  });

  /// Abre el bottom-sheet y retorna el resultado.
  /// Retorna null si el usuario cancela.
  static Future<DispatchResult?> show(
    BuildContext context, {
    required LatLng origin,
    bool notificationsEnabled = true,
  }) {
    return showModalBottomSheet<DispatchResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(_).viewInsets.bottom,
        ),
        child: EmergencyDispatchDialog(
          origin: origin,
          notificationsEnabled: notificationsEnabled,
        ),
      ),
    );
  }

  @override
  State<EmergencyDispatchDialog> createState() =>
      _EmergencyDispatchDialogState();
}

class _EmergencyDispatchDialogState extends State<EmergencyDispatchDialog> {
  final _placeSearch = PlaceSearchService();
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  List<PlaceSuggestion> _suggestions = [];
  bool _isSearching = false;
  bool _showMapPicker = false;

  GoogleMapController? _pickerMapCtrl;
  LatLng? _pickedDestination;
  String _pickedLabel = '';

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_searchFocus.hasFocus && _suggestions.isEmpty && _searchCtrl.text.isNotEmpty) {
      _onSearchChanged(_searchCtrl.text);
    }
  }

  // ── Autocompletado con debounce ───────────────────────────────
  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _searchPlaces(query);
    });
  }

  Future<void> _searchPlaces(String query) async {
    if (query.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }

    setState(() => _isSearching = true);
    try {
      final results = await _placeSearch.searchPlaces(query);
      if (mounted) setState(() => _suggestions = results);
    } catch (e) {
      // Mostrar el error para diagnóstico en lugar de fallar silenciosamente
      if (mounted) {
        setState(() => _suggestions = []);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al buscar: $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _selectSuggestion(PlaceSuggestion suggestion) async {
    setState(() => _isSearching = true);
    try {
      final result = await _placeSearch.getPlaceDetails(suggestion.placeId);
      _searchCtrl.text = suggestion.description;
      setState(() {
        _pickedDestination = result.coordinates;
        _pickedLabel = result.name.isNotEmpty ? result.name : suggestion.description;
        _suggestions = [];
      });
      _searchFocus.unfocus();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudieron obtener las coordenadas.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  // ── Selección en mapa ─────────────────────────────────────────
  void _toggleMapPicker() {
    setState(() {
      _showMapPicker = !_showMapPicker;
      if (_showMapPicker) {
        _searchFocus.unfocus();
        _suggestions = [];
      }
    });
  }

  void _onMapTapped(LatLng position) async {
    setState(() => _isSearching = true);
    final label = await _placeSearch.reverseGeocode(position);
    if (mounted) {
      setState(() {
        _pickedDestination = position;
        _pickedLabel = label;
        _searchCtrl.text = label;
        _isSearching = false;
      });
    }
  }

  // ── Acciones de confirmación ──────────────────────────────────
  void _confirmWithDestination() {
    if (_pickedDestination == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un destino primero.')),
      );
      return;
    }

    Navigator.of(context).pop(DispatchResult(
      hasFixedDestination: true,
      destination: _pickedDestination,
      destinationLabel: _pickedLabel.isNotEmpty ? _pickedLabel : null,
    ));
  }

  void _confirmSinDestino() {
    Navigator.of(context).pop(DispatchResult(
      hasFixedDestination: false,
    ));
  }

  void _cancel() {
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.removeListener(_onFocusChange);
    _searchFocus.dispose();
    _pickerMapCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.85),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SingleChildScrollView(
        reverse: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          // ── Handle ──────────────────────────────────────────────
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Título ──────────────────────────────────────────────
          Text('Configurar despacho', style: tt.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Selecciona el destino o inicia en ${AppConstants.openRouteModeLabel}.',
            style: tt.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),

          // ── Banner de notificaciones desactivadas (TASK-01) ──────
          if (!widget.notificationsEnabled) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.alertAnticipation.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.alertAnticipation.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.notifications_off,
                      color: AppColors.textPrimary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Notificaciones desactivadas. No verás el indicador '
                      'de baliza ni alertas operativas.',
                      style: tt.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        PermissionService().openAppSettings(),
                    child: const Text('Ajustes', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // ── Campo de búsqueda ───────────────────────────────────
          TextField(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Buscar destino (hospital, dirección...)',
              prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
              suffixIcon: _isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.map_outlined, color: AppColors.accent),
                      tooltip: 'Seleccionar en mapa',
                      onPressed: _toggleMapPicker,
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.inputBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.accent, width: 2),
              ),
            ),
          ),

          // ── Lista de sugerencias ─────────────────────────────────
          if (_suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => const Divider(
                  height: 1,
                  color: AppColors.divider,
                ),
                itemBuilder: (_, i) {
                  final s = _suggestions[i];
                  return ListTile(
                    leading: const Icon(Icons.location_on_outlined,
                        color: AppColors.accent),
                    title: Text(s.description, maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    onTap: () => _selectSuggestion(s),
                  );
                },
              ),
            ),
          ],

          // ── Mapa selector ───────────────────────────────────────
          if (_showMapPicker) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 200,
                child: GoogleMap(
                  onMapCreated: (ctrl) => _pickerMapCtrl = ctrl,
                  initialCameraPosition: CameraPosition(
                    target: _pickedDestination ?? widget.origin,
                    zoom: 14,
                  ),
                  onTap: _onMapTapped,
                  markers: _pickedDestination != null
                      ? {
                          Marker(
                            markerId: const MarkerId('picked_dest'),
                            position: _pickedDestination!,
                          ),
                        }
                      : {},
                ),
              ),
            ),
            if (_pickedDestination != null && _pickedLabel == 'Destino en mapa')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Lat: ${_pickedDestination!.latitude.toStringAsFixed(5)}, '
                  'Lng: ${_pickedDestination!.longitude.toStringAsFixed(5)}',
                  style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ),
          ],

          // ── Destino seleccionado ────────────────────────────────
          if (_pickedDestination != null && !_showMapPicker) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: AppColors.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _pickedLabel,
                      style: tt.bodyMedium?.copyWith(
                        color: AppColors.accentDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // ── Botón: Sin destino fijo (acción rápida prominente) ───
          OutlinedButton.icon(
            onPressed: _confirmSinDestino,
            icon: const Icon(Icons.navigation_outlined),
            label: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppConstants.openRouteModeLabel,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  AppConstants.openRouteModeHint,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary, width: 1.5),
              minimumSize: const Size.fromHeight(60),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Botón: Confirmar con destino ─────────────────────────
          ElevatedButton.icon(
            onPressed: _pickedDestination != null ? _confirmWithDestination : null,
            icon: const Icon(Icons.local_hospital),
            label: const Text(
              'Iniciar con destino',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.alertCritical,
              foregroundColor: AppColors.onPrimary,
              disabledBackgroundColor: AppColors.divider,
              disabledForegroundColor: AppColors.textDisabled,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // ── Cancelar ────────────────────────────────────────────
          TextButton(
            onPressed: _cancel,
            child: const Text('Cancelar'),
          ),
          ],
        ),
      ),
    );
  }
}
