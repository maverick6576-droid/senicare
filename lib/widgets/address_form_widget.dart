import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_typeahead/flutter_typeahead.dart';

class AddressFormWidget extends StatefulWidget {
  final String? initialAddress;
  final ValueChanged<String> onAddressChanged;

  const AddressFormWidget({
    super.key,
    this.initialAddress,
    required this.onAddressChanged,
  });

  @override
  State<AddressFormWidget> createState() => _AddressFormWidgetState();
}

class _AddressFormWidgetState extends State<AddressFormWidget> {
  final List<String> _provinces = [
    'A Coru\u00f1a', 'Álava', 'Albacete', 'Alicante', 'Almería', 'Asturias', 'Ávila', 'Badajoz', 
    'Illes Balears', 'Barcelona', 'Bizkaia', 'Burgos', 'Cáceres', 'Cádiz', 'Cantabria', 'Castellón', 
    'Ciudad Real', 'Córdoba', 'Cuenca', 'Gipuzkoa', 'Girona', 'Granada', 'Guadalajara', 'Huelva', 
    'Huesca', 'Jaén', 'La Rioja', 'Las Palmas', 'León', 'Lleida', 'Lugo', 'Madrid', 'Málaga', 
    'Murcia', 'Navarra', 'Ourense', 'Palencia', 'Pontevedra', 'Salamanca', 'Santa Cruz de Tenerife', 
    'Segovia', 'Sevilla', 'Soria', 'Tarragona', 'Teruel', 'Toledo', 'Valencia', 'Valladolid', 
    'Zamora', 'Zaragoza', 'Ceuta', 'Melilla'
  ];

  String _country = 'España';
  String? _province;
  final TextEditingController _cityCtrl = TextEditingController();
  final TextEditingController _streetCtrl = TextEditingController();
  final TextEditingController _numberCtrl = TextEditingController();

  String _lastStreetQuery = '';
  String _lastCityQuery = '';
  bool _suppressNotify = false;

  @override
  void initState() {
    super.initState();
    _parseInitialAddress(widget.initialAddress);

    _cityCtrl.addListener(_notifyChange);
    _streetCtrl.addListener(_notifyChange);
    _numberCtrl.addListener(_notifyChange);
  }

  @override
  void didUpdateWidget(covariant AddressFormWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialAddress != oldWidget.initialAddress &&
        widget.initialAddress != _composeCurrentAddress()) {
      _parseInitialAddress(widget.initialAddress);
    }
  }

  String _composeCurrentAddress() {
    if (_province == null ||
        _cityCtrl.text.trim().isEmpty ||
        _streetCtrl.text.trim().isEmpty) {
      return '';
    }
    var addr = _streetCtrl.text.trim();
    if (_numberCtrl.text.trim().isNotEmpty) {
      addr += ' ${_numberCtrl.text.trim()}';
    }
    return '$addr, ${_cityCtrl.text.trim()}, $_province, $_country';
  }

  String? _normalizeProvince(String raw) {
    final cleaned = raw.trim();
    if (_provinces.contains(cleaned)) return cleaned;
    final lower = cleaned.toLowerCase();
    const aliases = <String, String>{
      'comunidad de madrid': 'Madrid',
      'la coruña': 'A Coruña',
      'a coruna': 'A Coruña',
      'vizcaya': 'Bizkaia',
      'guipuzcoa': 'Gipuzkoa',
      'guipúzcoa': 'Gipuzkoa',
      'alava': 'Álava',
      'araba': 'Álava',
      'araba/álava': 'Álava',
      'islas baleares': 'Illes Balears',
      'baleares': 'Illes Balears',
      'orense': 'Ourense',
      'gerona': 'Girona',
      'lerida': 'Lleida',
      'lérida': 'Lleida',
      'región de murcia': 'Murcia',
      'region de murcia': 'Murcia',
      'principado de asturias': 'Asturias',
      'comunidad foral de navarra': 'Navarra',
      'navarra / nafarroa': 'Navarra',
      'castellon': 'Castellón',
      'almeria': 'Almería',
      'avila': 'Ávila',
      'caceres': 'Cáceres',
      'cadiz': 'Cádiz',
      'cordoba': 'Córdoba',
      'jaen': 'Jaén',
      'leon': 'León',
      'malaga': 'Málaga',
      'valencia / valència': 'Valencia',
      'alicante / alacant': 'Alicante',
      'castellón / castelló': 'Castellón',
    };
    if (aliases.containsKey(lower)) return aliases[lower];
    for (final p in _provinces) {
      if (p.toLowerCase() == lower) return p;
    }
    return null;
  }

  void _parseInitialAddress(String? rawAddress) {
    _suppressNotify = true;
    try {
      if (rawAddress == null || rawAddress.trim().isEmpty) {
        _country = 'España';
        _province = null;
        _cityCtrl.clear();
        _streetCtrl.clear();
        _numberCtrl.clear();
        return;
      }

      final parts = rawAddress
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      if (parts.length >= 4) {
        final rawCountry = parts.last.toLowerCase();
        _country = (rawCountry == 'españa' || rawCountry == 'spain')
            ? 'España'
            : 'España';

        // Find province scanning backwards from second-to-last part
        String? matchedProv;
        int provIdx = parts.length - 2;
        for (int i = parts.length - 1; i >= 1; i--) {
          final normalized = _normalizeProvince(parts[i]);
          if (normalized != null) {
            matchedProv = normalized;
            provIdx = i;
            break;
          }
        }
        _province = matchedProv;

        final cityIdx = (provIdx - 1).clamp(0, parts.length - 1);
        final cityCandidate = parts[cityIdx].replaceFirst(RegExp(r'^\d{5}\s+'), '').trim();
        _cityCtrl.text = cityIdx > 0 ? cityCandidate : '';

        final streetParts = cityIdx > 0 ? parts.sublist(0, cityIdx) : parts.sublist(0, provIdx);
        final streetAndNum = streetParts.join(', ').trim();
        final match = RegExp(r'^(.*?)(\d+.*)$').firstMatch(streetAndNum);
        if (match != null) {
          _streetCtrl.text = match.group(1)?.trim() ?? '';
          _numberCtrl.text = match.group(2)?.trim() ?? '';
        } else {
          _streetCtrl.text = streetAndNum;
          _numberCtrl.clear();
        }
      } else if (parts.length == 3) {
        _country = 'España';
        final lastLower = parts.last.toLowerCase();
        if (lastLower == 'españa' || lastLower == 'spain') {
          final prov = _normalizeProvince(parts[1]);
          _province = prov;
          _cityCtrl.text = parts[1].replaceFirst(RegExp(r'^\d{5}\s+'), '').trim();
        } else {
          final prov = _normalizeProvince(parts[2]);
          _province = prov;
          _cityCtrl.text = parts[1].replaceFirst(RegExp(r'^\d{5}\s+'), '').trim();
        }
        final match = RegExp(r'^(.*?)(\d+.*)$').firstMatch(parts[0]);
        if (match != null) {
          _streetCtrl.text = match.group(1)?.trim() ?? '';
          _numberCtrl.text = match.group(2)?.trim() ?? '';
        } else {
          _streetCtrl.text = parts[0];
          _numberCtrl.clear();
        }
      } else {
        _country = 'España';
        _province = null;
        _cityCtrl.clear();
        _numberCtrl.clear();
        _streetCtrl.text = rawAddress.trim();
      }
    } finally {
      _suppressNotify = false;
    }
  }

  void _notifyChange() {
    if (_suppressNotify) return;
    widget.onAddressChanged(_composeCurrentAddress());
  }

  Future<List<String>> _searchCityAsync(String query) async {
    if (query.length < 2) return [];
    
    _lastCityQuery = query;
    await Future.delayed(const Duration(milliseconds: 500));
    if (_lastCityQuery != query) return [];

    String searchQuery = query;
    if (_province != null) {
      searchQuery += ', $_province';
    }

    try {
      final uri = Uri.parse('https://photon.komoot.io/api/?q=${Uri.encodeComponent(searchQuery)}&limit=7&osm_tag=place');
      final response = await http
          .get(uri, headers: {'User-Agent': 'SeniCareApp/1.0 (senicare@flutter.dev)'})
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;
        
        Set<String> results = {};
        for (var feature in features) {
          final props = feature['properties'];
          if (props['name'] != null) {
            results.add(props['name'].toString());
          }
        }
        return results.toList();
      }
    } catch (e) {
      // ignore safely
    }
    return [];
  }

  Future<List<String>> _searchStreetAsync(String query) async {
    if (query.length < 3) return [];

    _lastStreetQuery = query;
    await Future.delayed(const Duration(milliseconds: 500));
    if (_lastStreetQuery != query) return [];

    String searchQuery = query;
    if (_cityCtrl.text.isNotEmpty) {
      searchQuery += ', ${_cityCtrl.text.trim()}';
    } else if (_province != null) {
      searchQuery += ', $_province';
    }

    try {
      final uri = Uri.parse('https://photon.komoot.io/api/?q=${Uri.encodeComponent(searchQuery)}&limit=7&osm_tag=highway');
      final response = await http
          .get(uri, headers: {'User-Agent': 'SeniCareApp/1.0 (senicare@flutter.dev)'})
          .timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final features = data['features'] as List;
        
        Set<String> results = {};
        for (var feature in features) {
          final props = feature['properties'];
          if (props['name'] != null) {
            results.add(props['name'].toString());
          }
        }
        return results.toList();
      }
    } catch (e) {
      // ignore safely
    }
    return [];
  }

  @override
  void dispose() {
    _cityCtrl.dispose();
    _streetCtrl.dispose();
    _numberCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _country,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'País', border: OutlineInputBorder()),
          items: ['España'].map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() => _country = val);
              _notifyChange();
            }
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _province,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Provincia', border: OutlineInputBorder()),
          hint: const Text('Selecciona una provincia', overflow: TextOverflow.ellipsis),
          items: _provinces.map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: (val) {
            setState(() => _province = val);
            _notifyChange();
          },
          validator: (v) => v == null ? 'Requerido' : null,
        ),
        const SizedBox(height: 16),
        
        // AUTOCOMPLETE DE CIUDAD USANDO FLUTTER_TYPEAHEAD
        TypeAheadField<String>(
          controller: _cityCtrl,
          builder: (context, controller, focusNode) {
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              decoration: const InputDecoration(
                labelText: 'Ciudad / Localidad',
                border: OutlineInputBorder(),
                helperText: 'Busca tu ciudad (Ej: Barcelona)',
              ),
              validator: (v) => v!.isEmpty ? 'Requerido' : null,
            );
          },
          suggestionsCallback: (pattern) async {
            return await _searchCityAsync(pattern);
          },
          itemBuilder: (context, String suggestion) {
            return ListTile(
              title: Text(suggestion),
            );
          },
          onSelected: (String suggestion) {
            _cityCtrl.text = suggestion;
          },
          emptyBuilder: (context) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('No se encontraron ciudades.'),
            );
          },
        ),
        const SizedBox(height: 16),
        
        // AUTOCOMPLETE DE CALLE USANDO FLUTTER_TYPEAHEAD
        TypeAheadField<String>(
          controller: _streetCtrl,
          builder: (context, controller, focusNode) {
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              decoration: const InputDecoration(
                labelText: 'Calle o Avenida',
                border: OutlineInputBorder(),
                helperText: 'Escribe y selecciona de la lista si aparece',
              ),
              validator: (v) => v!.isEmpty ? 'Requerido' : null,
            );
          },
          suggestionsCallback: (pattern) async {
            return await _searchStreetAsync(pattern);
          },
          itemBuilder: (context, String suggestion) {
            return ListTile(
              title: Text(suggestion),
            );
          },
          onSelected: (String suggestion) {
            _streetCtrl.text = suggestion;
            FocusScope.of(context).unfocus();
          },
          emptyBuilder: (context) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('No se encontraron calles.'),
            );
          },
        ),
        const SizedBox(height: 16),
        
        TextFormField(
          controller: _numberCtrl,
          decoration: const InputDecoration(labelText: 'Número, Piso, Puerta (Opcional)', border: OutlineInputBorder()),
        ),
      ],
    );
  }
}
