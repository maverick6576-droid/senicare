import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/screens/job_offers/create_offer_screen.dart';
import 'package:senicare/screens/job_offers/offer_detail_screen.dart';

class OffersHubScreen extends StatelessWidget {
  const OffersHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isClient = context.watch<AuthNotifier>().currentRole == 'client';
    
    if (isClient) return const _ClientOffersView();
    return const _CaregiverOffersView();
  }
}

class _ClientOffersView extends StatefulWidget {
  const _ClientOffersView();

  @override
  State<_ClientOffersView> createState() => _ClientOffersViewState();
}

class _ClientOffersViewState extends State<_ClientOffersView> {
  final ScrollController _scrollActive = ScrollController();
  final ScrollController _scrollHistory = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollActive.addListener(_onScroll);
    _scrollHistory.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollActive.hasClients && _scrollActive.position.pixels >= _scrollActive.position.maxScrollExtent - 200) {
      context.read<JobOfferNotifier>().loadMoreClientOffers();
    }
    if (_scrollHistory.hasClients && _scrollHistory.position.pixels >= _scrollHistory.position.maxScrollExtent - 200) {
      context.read<JobOfferNotifier>().loadMoreClientOffers();
    }
  }

  @override
  void dispose() {
    _scrollActive.dispose();
    _scrollHistory.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offers = context.watch<JobOfferNotifier>().clientOffers;
    final appsMap = context.watch<JobOfferNotifier>().applicationsByOffer;

    final activeOffers = offers.where((o) => o.status == JobOfferStatus.open && !o.isExpired).toList();
    final historyOffers = offers.where((o) => o.status != JobOfferStatus.open || o.isExpired).toList();

    Widget buildList(List<JobOffer> list, ScrollController controller) {
      return RefreshIndicator(
        onRefresh: () async {
          context.read<JobOfferNotifier>().initForClient(context.read<AuthNotifier>().currentUserId ?? '');
        },
        child: list.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: const Center(child: Text('No tienes ofertas en esta sección')),
                  )
                ],
              )
            : ListView.builder(
                controller: controller,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: list.length,
                itemBuilder: (context, index) {
                  final offer = list[index];
                  final appsCount = (appsMap[offer.id] ?? []).length;
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ListTile(
                      title: Text(offer.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${offer.isExpired ? "CADUCADA" : offer.status.toString().split('.').last.toUpperCase()}   ${offer.pricePerHour}€/h'),
                      trailing: appsCount > 0
                          ? Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                '$appsCount',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            )
                          : null,
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => OfferDetailScreen(offer: offer)));
                      },
                    ),
                  );
                },
              ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mis Ofertas de Trabajo'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Activas'),
              Tab(text: 'Historial'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            buildList(activeOffers, _scrollActive),
            buildList(historyOffers, _scrollHistory),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateOfferScreen()));
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _CaregiverOffersView extends StatefulWidget {
  const _CaregiverOffersView();

  @override
  State<_CaregiverOffersView> createState() => _CaregiverOffersViewState();
}

class _CaregiverOffersViewState extends State<_CaregiverOffersView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      context.read<JobOfferNotifier>().loadMoreNearbyOffers();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offers = context.watch<JobOfferNotifier>().nearbyOffers.where((o) => !o.isExpired).toList();
    
    return Scaffold(
      appBar: AppBar(title: const Text('Ofertas Cercanas')),
      body: RefreshIndicator(
        onRefresh: () async {
          final auth = context.read<AuthNotifier>();
          final location = context.read<LocationNotifier>();
          final lat = auth.currentCaregiver?.latitude ?? location.latitude;
          final lng = auth.currentCaregiver?.longitude ?? location.longitude;
          final maxDistance = auth.currentCaregiver?.maxDistanceRadius ?? 50.0;
          if (lat != null && lng != null) {
            context.read<JobOfferNotifier>().initForCaregiver(lat, lng, maxDistance);
          }
        },
        child: offers.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.6,
                    child: const Center(child: Text('No hay ofertas abiertas cerca de ti')),
                  )
                ],
              )
            : ListView.builder(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: offers.length,
                itemBuilder: (context, index) {
                  final offer = offers[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: InkWell(
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => OfferDetailScreen(offer: offer)));
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (offer.isUrgent)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                                child: const Text('⏰ URGENTE (+10%)', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                            if (offer.isUrgent) const SizedBox(height: 8),
                            Text(
                              'Familia: ${offer.clientName.trim().split(RegExp(r'\s+')).length > 1 ? offer.clientName.trim().split(RegExp(r'\s+'))[1] : offer.clientName}',
                              style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 4),
                            Text(offer.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Text(offer.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${offer.pricePerHour} €/h', style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 16)),
                                Text('${offer.totalHours}h en total', style: const TextStyle(color: Colors.grey)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

