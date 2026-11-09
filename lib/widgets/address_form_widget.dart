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

  @override
  void initState() {
    super.initState();
    _parseInitialAddress();
    
    _cityCtrl.addListener(_notifyChange);
    _streetCtrl.addListener(_notifyChange);
    _numberCtrl.addListener(_notifyChange);
  }

  void _parseInitialAddress() {
    if (widget.initialAddress == null || widget.initialAddress!.isEmpty) return;
    
    List<String> parts = widget.initialAddress!.split(',').map((e) => e.trim()).toList();
    if (parts.length >= 4) {
      _country = parts.last;
      _province = parts[parts.length - 2];
      if (!_provinces.contains(_province)) _province = null;
      _cityCtrl.text = parts[parts.length - 3];
      
      String streetAndNum = parts.sublist(0, parts.length - 3).join(', ');
      final match = RegExp(r'^(.*?)(\d+.*)$').firstMatch(streetAndNum);
      if (match != null) {
        _streetCtrl.text = match.group(1)?.trim() ?? '';
        _numberCtrl.text = match.group(2)?.trim() ?? '';
      } else {
        _streetCtrl.text = streetAndNum;
      }
    } else {
      _streetCtrl.text = widget.initialAddress!;
    }
  }

  void _notifyChange() {
    if (_province == null || _cityCtrl.text.trim().isEmpty || _streetCtrl.text.trim().isEmpty) {
      widget.onAddressChanged('');
      return;
    }
    
    String addr = _streetCtrl.text.trim();
    if (_numberCtrl.text.trim().isNotEmpty) {
      addr += ' ${_numberCtrl.text.trim()}';
    }
    addr += ', ${_cityCtrl.text.trim()}, $_province, $_country';
    
    widget.onAddressChanged(addr);
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
      final response = await http.get(uri, headers: {
        'User-Agent': 'SeniCareApp/1.0 (senicare@flutter.dev)'
      });
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
      final response = await http.get(uri, headers: {
        'User-Agent': 'SeniCareApp/1.0 (senicare@flutter.dev)'
      });
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
          decoration: const InputDecoration(labelText: 'País', border: OutlineInputBorder()),
          items: ['España'].map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value),
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
          decoration: const InputDecoration(labelText: 'Provincia', border: OutlineInputBorder()),
          hint: const Text('Selecciona una provincia'),
          items: _provinces.map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Text(value),
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
