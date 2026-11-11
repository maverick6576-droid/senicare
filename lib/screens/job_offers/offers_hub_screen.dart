import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:senicare/core/core.dart';
import 'package:senicare/models/models.dart';
import 'package:senicare/repositories/firebase/firestore_stats_repository.dart';
import 'package:senicare/screens/caregiver_profile_edit_screen.dart';
import 'package:senicare/screens/job_offers/create_offer_screen.dart';
import 'package:senicare/screens/job_offers/offer_detail_screen.dart';
import 'package:senicare/widgets/widgets.dart';

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
    _scrollActive.addListener(() => _onScroll(_scrollActive));
    _scrollHistory.addListener(() => _onScroll(_scrollHistory));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final uid = context.read<AuthNotifier>().currentUserId;
      if (uid != null && uid.isNotEmpty) {
        context.read<JobOfferNotifier>().initForClient(uid);
      }
    });
  }

  void _onScroll(ScrollController controller) {
    if (!controller.hasClients) return;
    if (controller.position.pixels >= controller.position.maxScrollExtent - 180) {
      context.read<JobOfferNotifier>().loadMoreClientOffers();
    }
  }

  @override
  void dispose() {
    _scrollActive.dispose();
    _scrollHistory.dispose();
    super.dispose();
  }

  void _openCreateOffer([JobOffer? template]) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreateOfferScreen(initialOffer: template)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final jobNotifier = context.watch<JobOfferNotifier>();
    final seniorMode = context.watch<ConfigNotifier>().seniorMode;
    final offers = jobNotifier.clientOffers;
    final appsMap = jobNotifier.applicationsByOffer;

    final activeOffers = offers
        .where((o) => o.status == JobOfferStatus.inProgress || (o.status == JobOfferStatus.open && !o.isExpired))
        .toList()
      ..sort((a, b) {
        int pendingCount(JobOffer o) =>
            (appsMap[o.id] ?? const []).where((app) => app.status == JobApplicationStatus.pending).length;

        final aPending = a.status == JobOfferStatus.open ? pendingCount(a) : 0;
        final bPending = b.status == JobOfferStatus.open ? pendingCount(b) : 0;
        if ((aPending > 0) != (bPending > 0)) {
          return aPending > 0 ? -1 : 1;
        }
        if (a.status != b.status) {
          return a.status == JobOfferStatus.inProgress ? -1 : 1;
        }
        return a.startDate.compareTo(b.startDate);
      });

    final historyOffers = offers
        .where((o) => o.status != JobOfferStatus.inProgress && (o.status != JobOfferStatus.open || o.isExpired))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final pendingToReview = activeOffers.fold<int>(
      0,
      (sum, o) =>
          sum +
          (o.status == JobOfferStatus.open
              ? (appsMap[o.id] ?? const []).where((a) => a.status == JobApplicationStatus.pending).length
              : 0),
    );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundNeutral,
        body: Column(
          children: [
            Container(
              color: Colors.white,
              child: TabBar(
                labelColor: AppTheme.primary,
                unselectedLabelColor: AppTheme.slateMuted,
                indicatorColor: AppTheme.primary,
                indicatorWeight: 3,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: seniorMode ? 16 : 14.5,
                ),
                tabs: [
                  Tab(text: 'Activas (${activeOffers.length})'),
                  Tab(text: 'Historial (${historyOffers.length})'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildOfferList(
                    context: context,
                    jobNotifier: jobNotifier,
                    offers: activeOffers,
                    appsMap: appsMap,
                    controller: _scrollActive,
                    isActiveTab: true,
                    pendingCandidatesCount: pendingToReview,
                    seniorMode: seniorMode,
                  ),
                  _buildOfferList(
                    context: context,
                    jobNotifier: jobNotifier,
                    offers: historyOffers,
                    appsMap: appsMap,
                    controller: _scrollHistory,
                    isActiveTab: false,
                    pendingCandidatesCount: pendingToReview,
                    seniorMode: seniorMode,
                  ),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          key: AppTutorialTargets.maybeClientOf(context)?.clientOffersFabKey,
          heroTag: 'client_new_offer_fab',
          onPressed: () => _openCreateOffer(),
          icon: const Icon(Icons.add_rounded),
          label: Text(
            'Publicar Oferta',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: seniorMode ? 16 : 14.5,
            ),
          ),
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildOfferList({
    required BuildContext context,
    required JobOfferNotifier jobNotifier,
    required List<JobOffer> offers,
    required Map<String, List<JobApplication>> appsMap,
    required ScrollController controller,
    required bool isActiveTab,
    required int pendingCandidatesCount,
    required bool seniorMode,
  }) {
    if (jobNotifier.isLoadingClientOffers && jobNotifier.clientOffers.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Cargando tus ofertas...', style: TextStyle(color: AppTheme.slateMuted)),
            ],
          ),
        ),
      );
    }

    if (jobNotifier.clientError != null && jobNotifier.clientOffers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: AppTheme.modernCardDecoration(),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off_rounded, size: 44, color: Colors.red.shade600),
                const SizedBox(height: 12),
                Text(
                  jobNotifier.clientError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: seniorMode ? 16 : 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.darkSlate,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () {
                    final uid = context.read<AuthNotifier>().currentUserId;
                    if (uid != null && uid.isNotEmpty) {
                      jobNotifier.initForClient(uid, forceRefresh: true);
                    }
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => context.read<JobOfferNotifier>().refreshClientOffers(),
      child: offers.isEmpty
          ? ListView(
              controller: controller,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
              children: [
                if (jobNotifier.clientError != null) ...[
                  _ClientErrorInlineBanner(
                    message: jobNotifier.clientError!,
                    seniorMode: seniorMode,
                    onRetry: () => jobNotifier.refreshClientOffers(),
                  ),
                  const SizedBox(height: 12),
                ],
                _ClientEmptyOffersCard(
                  isActiveTab: isActiveTab,
                  seniorMode: seniorMode,
                  onCreateOffer: () => _openCreateOffer(),
                ),
              ],
            )
          : ListView.builder(
              controller: controller,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              itemCount: offers.length + 1 + (jobNotifier.hasMoreClientOffers ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _ClientOffersGuideBanner(
                    seniorMode: seniorMode,
                    isActiveTab: isActiveTab,
                    pendingCandidatesCount: pendingCandidatesCount,
                    errorMessage: jobNotifier.clientError,
                    onRetry: () => jobNotifier.refreshClientOffers(),
                  );
                }
                final offerIndex = index - 1;
                if (offerIndex >= offers.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  );
                }
                final offer = offers[offerIndex];
                final apps = appsMap[offer.id] ?? const [];
                return _ClientOfferCard(
                  offer: offer,
                  applications: apps,
                  seniorMode: seniorMode,
                  onOpenDetail: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => OfferDetailScreen(offer: offer)),
                    );
                  },
                  onRepublish: () => _openCreateOffer(offer),
                );
              },
            ),
    );
  }
}

class _ClientErrorInlineBanner extends StatelessWidget {
  final String message;
  final bool seniorMode;
  final VoidCallback onRetry;

  const _ClientErrorInlineBanner({
    required this.message,
    required this.seniorMode,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.red.shade900, fontSize: seniorMode ? 14 : 12.5),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}

class _ClientOffersGuideBanner extends StatelessWidget {
  final bool seniorMode;
  final bool isActiveTab;
  final int pendingCandidatesCount;
  final String? errorMessage;
  final VoidCallback onRetry;

  const _ClientOffersGuideBanner({
    required this.seniorMode,
    required this.isActiveTab,
    required this.pendingCandidatesCount,
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final hasPending = isActiveTab && pendingCandidatesCount > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          if (errorMessage != null) ...[
            _ClientErrorInlineBanner(
              message: errorMessage!,
              seniorMode: seniorMode,
              onRetry: onRetry,
            ),
            const SizedBox(height: 10),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: hasPending ? Colors.amber.shade50 : AppTheme.primarySurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: hasPending
                    ? Colors.amber.shade300
                    : AppTheme.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasPending ? Icons.notifications_active_rounded : Icons.verified_user_rounded,
                  color: hasPending ? Colors.amber.shade900 : AppTheme.primary,
                  size: seniorMode ? 24 : 21,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    !isActiveTab
                        ? 'Aquí tienes tus ofertas anteriores. Puedes volver a publicar cualquiera con un toque.'
                        : hasPending
                            ? 'Tienes $pendingCandidatesCount candidato${pendingCandidatesCount == 1 ? '' : 's'} por revisar. Toca una oferta para ver perfiles y chatear.'
                            : 'Publicar es gratis y sin compromiso. Solo pagas cuando elijas al cuidador que más confianza te dé.',
                    style: TextStyle(
                      fontSize: seniorMode ? 14.5 : 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.darkSlate,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ClientEmptyOffersCard extends StatelessWidget {
  final bool isActiveTab;
  final bool seniorMode;
  final VoidCallback onCreateOffer;

  const _ClientEmptyOffersCard({
    required this.isActiveTab,
    required this.seniorMode,
    required this.onCreateOffer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: AppTheme.modernCardDecoration(),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppTheme.primarySurface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isActiveTab ? Icons.campaign_rounded : Icons.history_rounded,
              size: 40,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            isActiveTab ? 'Aún no tienes ofertas activas' : 'Tu historial está vacío',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: seniorMode ? 19 : 17,
              fontWeight: FontWeight.w800,
              color: AppTheme.darkSlate,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isActiveTab
                ? 'Publica gratis el horario y el precio que ofreces. Los cuidadores de tu zona podrán responderte.'
                : 'Aquí quedarán guardadas tus ofertas completadas, canceladas o con fecha pasada.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: seniorMode ? 15 : 13.5,
              color: AppTheme.slateMuted,
              height: 1.4,
            ),
          ),
          if (isActiveTab) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: seniorMode ? 52 : 46,
              child: FilledButton.icon(
                onPressed: onCreateOffer,
                icon: const Icon(Icons.add_rounded),
                label: Text(
                  'Publicar mi primera oferta',
                  style: TextStyle(
                    fontSize: seniorMode ? 16 : 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ClientOfferCard extends StatelessWidget {
  final JobOffer offer;
  final List<JobApplication> applications;
  final bool seniorMode;
  final VoidCallback onOpenDetail;
  final VoidCallback onRepublish;

  const _ClientOfferCard({
    required this.offer,
    required this.applications,
    required this.seniorMode,
    required this.onOpenDetail,
    required this.onRepublish,
  });

  ({String label, Color bg, Color border, Color text}) _statusStyle(int pendingAppsCount) {
    if (offer.isExpired) {
      return (
        label: 'Fecha pasada',
        bg: Colors.grey.shade100,
        border: Colors.grey.shade300,
        text: Colors.grey.shade700,
      );
    }
    switch (offer.status) {
      case JobOfferStatus.open:
        if (pendingAppsCount > 0) {
          return (
            label: '$pendingAppsCount candidato${pendingAppsCount == 1 ? '' : 's'}',
            bg: Colors.amber.shade50,
            border: Colors.amber.shade400,
            text: Colors.amber.shade900,
          );
        }
        return (
          label: 'Buscando cuidador',
          bg: AppTheme.primarySurface,
          border: AppTheme.primary.withValues(alpha: 0.35),
          text: AppTheme.primary,
        );
      case JobOfferStatus.inProgress:
        return (
          label: 'Cuidador confirmado',
          bg: Colors.green.shade50,
          border: Colors.green.shade300,
          text: Colors.green.shade800,
        );
      case JobOfferStatus.completed:
        return (
          label: 'Finalizada',
          bg: Colors.teal.shade50,
          border: Colors.teal.shade200,
          text: Colors.teal.shade800,
        );
      case JobOfferStatus.cancelled:
        return (
          label: 'Cancelada',
          bg: Colors.red.shade50,
          border: Colors.red.shade200,
          text: Colors.red.shade700,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = applications.where((a) => a.status == JobApplicationStatus.pending).length;
    final acceptedApp = applications.where((a) => a.status == JobApplicationStatus.accepted).firstOrNull;
    final status = _statusStyle(pendingCount);
    final totalEstimate = offer.pricePerHour * offer.totalHours;
    final d = offer.startDate;
    final dateText =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} • ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: pendingCount > 0 && offer.status == JobOfferStatus.open && !offer.isExpired
              ? Colors.amber.shade300
              : Colors.grey.shade200,
          width: pendingCount > 0 && offer.status == JobOfferStatus.open && !offer.isExpired ? 1.4 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpenDetail,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      offer.title,
                      style: TextStyle(
                        fontSize: seniorMode ? 18.5 : 16.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.darkSlate,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: status.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: status.border),
                    ),
                    child: Text(
                      status.label,
                      style: TextStyle(
                        fontSize: seniorMode ? 13 : 11.5,
                        fontWeight: FontWeight.w800,
                        color: status.text,
                      ),
                    ),
                  ),
                ],
              ),
              if (offer.isUrgent && offer.status == JobOfferStatus.open && !offer.isExpired) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.flash_on_rounded, size: 14, color: Colors.orange.shade800),
                      const SizedBox(width: 4),
                      Text(
                        'Urgente (<24h)',
                        style: TextStyle(
                          fontSize: seniorMode ? 12.5 : 11.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 15, color: AppTheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '$dateText (${offer.totalHours}h)',
                      style: TextStyle(
                        fontSize: seniorMode ? 15 : 13.5,
                        color: AppTheme.darkSlate,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.euro_rounded, size: 15, color: AppTheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${offer.pricePerHour.toStringAsFixed(2)} €/h  •  Total ${totalEstimate.toStringAsFixed(0)} €',
                      style: TextStyle(
                        fontSize: seniorMode ? 15 : 13.5,
                        color: AppTheme.slateMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (acceptedApp != null && offer.status == JobOfferStatus.inProgress) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Cuidador elegido: ${acceptedApp.caregiverName}',
                    style: TextStyle(
                      fontSize: seniorMode ? 14.5 : 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.green.shade900,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (offer.isExpired || offer.status == JobOfferStatus.cancelled)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onRepublish,
                        icon: const Icon(Icons.replay_rounded, size: 18),
                        label: const Text(
                          'Volver a publicar',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: onOpenDetail,
                      child: const Text('Ver detalle'),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: pendingCount > 0 && offer.status == JobOfferStatus.open
                      ? FilledButton.icon(
                          onPressed: onOpenDetail,
                          icon: const Icon(Icons.people_alt_rounded, size: 18),
                          label: Text(
                            'Revisar $pendingCount candidato${pendingCount == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: seniorMode ? 15.5 : 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : OutlinedButton(
                          onPressed: onOpenDetail,
                          child: Text(
                            offer.status == JobOfferStatus.inProgress
                                ? 'Ver cuidador y chatear'
                                : 'Ver detalle de la oferta',
                            style: TextStyle(
                              fontSize: seniorMode ? 15 : 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _CaregiverOfferFilter { all, urgentOnly, highestPay }

class _CaregiverOffersView extends StatefulWidget {
  const _CaregiverOffersView();

  @override
  State<_CaregiverOffersView> createState() => _CaregiverOffersViewState();
}

class _CaregiverOffersViewState extends State<_CaregiverOffersView> {
  final ScrollController _scrollController = ScrollController();
  _CaregiverOfferFilter _selectedFilter = _CaregiverOfferFilter.all;
  DateTime _lastLoadMoreAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureInitialSync());
  }

  Future<void> _ensureInitialSync() async {
    if (!mounted) return;
    final auth = context.read<AuthNotifier>();
    final location = context.read<LocationNotifier>();
    final jobOffers = context.read<JobOfferNotifier>();

    var lat = auth.currentCaregiver?.latitude ?? location.latitude;
    var lng = auth.currentCaregiver?.longitude ?? location.longitude;
    if (lat == null || lng == null) {
      await location.initLocation();
      if (!mounted) return;
      lat = auth.currentCaregiver?.latitude ?? location.latitude;
      lng = auth.currentCaregiver?.longitude ?? location.longitude;
    }

    final maxDistance = auth.currentCaregiver?.maxDistanceRadius ?? 50.0;
    if (lat != null && lng != null) {
      jobOffers.initForCaregiver(
        lat,
        lng,
        maxDistance,
        caregiverId: auth.currentUserId,
      );
    }
    if (auth.currentUserId != null) {
      await jobOffers.refreshMyApplications(auth.currentUserId);
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;

    if (_scrollController.position.pixels >= maxScroll - 180) {
      final now = DateTime.now();
      if (now.difference(_lastLoadMoreAt).inMilliseconds > 800) {
        _lastLoadMoreAt = now;
        context.read<JobOfferNotifier>().loadMoreNearbyOffers();
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleRefresh() async {
    final auth = context.read<AuthNotifier>();
    final location = context.read<LocationNotifier>();
    final jobOffers = context.read<JobOfferNotifier>();

    await auth.reloadRole();
    var lat = auth.currentCaregiver?.latitude ?? location.latitude;
    var lng = auth.currentCaregiver?.longitude ?? location.longitude;

    if (lat == null || lng == null) {
      await location.initLocation();
      lat = auth.currentCaregiver?.latitude ?? location.latitude;
      lng = auth.currentCaregiver?.longitude ?? location.longitude;
    }

    final maxDistance = auth.currentCaregiver?.maxDistanceRadius ?? 50.0;
    if (lat != null && lng != null) {
      await jobOffers.refreshNearbyOffers(
        lat,
        lng,
        maxDistance,
        caregiverId: auth.currentUserId,
      );
    } else if (auth.currentUserId != null) {
      await jobOffers.refreshMyApplications(auth.currentUserId);
    }
  }

  String _formatOfferSchedule(JobOffer offer) {
    final dt = offer.startDate;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final targetDay = DateTime(dt.year, dt.month, dt.day);
    final hhmm = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    String dayLabel;
    if (targetDay == today) {
      dayLabel = 'Hoy';
    } else if (targetDay == tomorrow) {
      dayLabel = 'Mañana';
    } else {
      const weekdays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
      const months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
      dayLabel = '${weekdays[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]}';
    }

    final base = '$dayLabel a las $hhmm • ${offer.totalHours}h';
    if (offer.isRecurring && offer.recurringWeeks > 0) {
      return '$base (${offer.recurringWeeks} sem.)';
    }
    return base;
  }

  List<JobOffer> _applyFilter(List<JobOffer> source) {
    final filtered = source.where((o) {
      if (o.isExpired || o.status != JobOfferStatus.open) return false;
      if (_selectedFilter == _CaregiverOfferFilter.urgentOnly) return o.isUrgent;
      return true;
    }).toList();

    if (_selectedFilter == _CaregiverOfferFilter.highestPay) {
      filtered.sort((a, b) {
        final priceCmp = b.pricePerHour.compareTo(a.pricePerHour);
        if (priceCmp != 0) return priceCmp;
        return a.startDate.compareTo(b.startDate);
      });
    }
    return filtered;
  }

  void _openProfileScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CaregiverProfileEditScreen()),
    ).then((_) {
      if (mounted) _handleRefresh();
    });
  }

  void _openOfferDetail(JobOffer offer) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => OfferDetailScreen(offer: offer)),
    ).then((_) {
      if (!mounted) return;
      final uid = context.read<AuthNotifier>().currentUserId;
      if (uid != null) {
        context.read<JobOfferNotifier>().refreshMyApplications(uid);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final location = context.watch<LocationNotifier>();
    final jobOfferState = context.watch<JobOfferNotifier>();
    final caregiver = auth.currentCaregiver;

    final lat = caregiver?.latitude ?? location.latitude;
    final lng = caregiver?.longitude ?? location.longitude;
    final maxDistance = caregiver?.maxDistanceRadius ?? 50.0;

    final availableOffers = _applyFilter(jobOfferState.nearbyOffers);
    final myApps = jobOfferState.myApplications;
    final myAppsMap = jobOfferState.myApplicationsByOfferId;
    final unappliedCount = jobOfferState.nearbyOffers
        .where((o) => !o.isExpired && o.status == JobOfferStatus.open && !myAppsMap.containsKey(o.id))
        .length;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Column(
          children: [
            Container(
              color: Colors.white,
              child: TabBar(
                labelColor: AppTheme.primary,
                unselectedLabelColor: AppTheme.slateMuted,
                indicatorColor: AppTheme.primary,
                indicatorWeight: 3,
                labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                tabs: [
                  Tab(
                    text: unappliedCount > 0 ? 'Disponibles ($unappliedCount)' : 'Disponibles',
                  ),
                  Tab(
                    text: myApps.isNotEmpty ? 'Mis Solicitudes (${myApps.length})' : 'Mis Solicitudes',
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _buildAvailableTab(
                    context: context,
                    caregiver: caregiver,
                    jobOfferState: jobOfferState,
                    offers: availableOffers,
                    myAppsMap: myAppsMap,
                    lat: lat,
                    lng: lng,
                    maxDistance: maxDistance,
                  ),
                  _buildMyApplicationsTab(
                    context: context,
                    jobOfferState: jobOfferState,
                    entries: myApps,
                    lat: lat,
                    lng: lng,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvailableTab({
    required BuildContext context,
    required CaregiverProfile? caregiver,
    required JobOfferNotifier jobOfferState,
    required List<JobOffer> offers,
    required Map<String, JobApplication> myAppsMap,
    required double? lat,
    required double? lng,
    required double maxDistance,
  }) {
    final banner = _buildQualificationBanner(caregiver);

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              key: TutorialScope.maybeOf(context)?.offersHeaderKey,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Ofertas cerca de ti',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppTheme.darkSlate),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Toca una oferta para ver los detalles y postularte',
                              style: TextStyle(fontSize: 13, color: AppTheme.slateMuted),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primarySurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                        ),
                        child: Text(
                          'Radio ${maxDistance.round()} km',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary),
                        ),
                      ),
                    ],
                  ),
                  if (banner != null) ...[
                    const SizedBox(height: 14),
                    banner,
                  ],
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip(
                          label: 'Todas',
                          icon: Icons.list_alt_rounded,
                          selected: _selectedFilter == _CaregiverOfferFilter.all,
                          onSelected: () => setState(() => _selectedFilter = _CaregiverOfferFilter.all),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          label: 'Urgentes ⚡',
                          icon: Icons.flash_on_rounded,
                          selected: _selectedFilter == _CaregiverOfferFilter.urgentOnly,
                          onSelected: () => setState(() => _selectedFilter = _CaregiverOfferFilter.urgentOnly),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          label: 'Mejor pagadas €',
                          icon: Icons.euro_rounded,
                          selected: _selectedFilter == _CaregiverOfferFilter.highestPay,
                          onSelected: () => setState(() => _selectedFilter = _CaregiverOfferFilter.highestPay),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (jobOfferState.isLoadingNearby && offers.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: AppTheme.primary),
                    SizedBox(height: 14),
                    Text('Buscando ofertas cercanas...', style: TextStyle(color: AppTheme.slateMuted)),
                  ],
                ),
              ),
            )
          else if (jobOfferState.nearbyError != null && offers.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildErrorState(jobOfferState.nearbyError!),
            )
          else if (offers.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyAvailableState(maxDistance: maxDistance, hasLocation: lat != null && lng != null),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final offer = offers[index];
                    final app = myAppsMap[offer.id];
                    final distKm = (lat != null && lng != null)
                        ? calculateDistance(lat, lng, offer.clientLatitude, offer.clientLongitude)
                        : null;
                    return _buildOfferCard(
                      offer: offer,
                      application: app,
                      distanceKm: distKm,
                      isApplicationsTab: false,
                    );
                  },
                  childCount: offers.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMyApplicationsTab({
    required BuildContext context,
    required JobOfferNotifier jobOfferState,
    required List<CaregiverOfferApplication> entries,
    required double? lat,
    required double? lng,
  }) {
    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: jobOfferState.isLoadingMyApplications && entries.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : entries.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.62,
                      child: Builder(
                        builder: (tabContext) => Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(18),
                                  decoration: const BoxDecoration(
                                    color: AppTheme.primarySurface,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.work_history_outlined, size: 42, color: AppTheme.primary),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Aún no tienes solicitudes',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.darkSlate),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Cuando te postules a una oferta de una familia, podrás seguir aquí si estás pendiente o si te han seleccionado.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 14, color: AppTheme.slateMuted, height: 1.4),
                                ),
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  onPressed: () {
                                    DefaultTabController.of(tabContext).animateTo(0);
                                  },
                                  icon: const Icon(Icons.search_rounded),
                                  label: const Text('Ver ofertas disponibles'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final distKm = (lat != null && lng != null)
                        ? calculateDistance(lat, lng, entry.offer.clientLatitude, entry.offer.clientLongitude)
                        : null;
                    return _buildOfferCard(
                      offer: entry.offer,
                      application: entry.application,
                      distanceKm: distKm,
                      isApplicationsTab: true,
                    );
                  },
                ),
    );
  }

  Widget? _buildQualificationBanner(CaregiverProfile? caregiver) {
    if (caregiver == null) return null;

    if (caregiver.accountStatus == 'suspended') {
      return _buildInfoBanner(
        icon: Icons.block_rounded,
        color: Colors.red.shade800,
        bgColor: Colors.red.shade50,
        borderColor: Colors.red.shade300,
        title: 'Cuenta suspendida',
        message: 'Puedes consultar las ofertas, pero tu cuenta está suspendida por incomparecencias previas.',
      );
    }

    if (caregiver.blockedUntil != null && caregiver.blockedUntil!.isAfter(DateTime.now())) {
      final until = caregiver.blockedUntil!;
      final untilStr =
          '${until.day.toString().padLeft(2, '0')}/${until.month.toString().padLeft(2, '0')}/${until.year}';
      return _buildInfoBanner(
        icon: Icons.timer_off_outlined,
        color: Colors.orange.shade900,
        bgColor: Colors.orange.shade50,
        borderColor: Colors.orange.shade300,
        title: 'Postulación pausada temporalmente',
        message: 'Podrás volver a enviar solicitudes a partir del $untilStr.',
      );
    }

    final isVerified = caregiver.verified || caregiver.verificationStatus == 'approved';
    final missingDocs = <String>[];
    if (caregiver.dniUrl.trim().isEmpty) missingDocs.add('DNI');
    if (caregiver.criminalRecordUrl.trim().isEmpty) missingDocs.add('Antecedentes');
    if (!caregiver.hasStripeAccount) missingDocs.add('Cuenta de cobro');

    if (caregiver.verificationStatus == 'rejected') {
      return _buildInfoBanner(
        icon: Icons.error_outline_rounded,
        color: Colors.red.shade800,
        bgColor: Colors.red.shade50,
        borderColor: Colors.red.shade300,
        title: 'Revisión de perfil requerida',
        message: 'Corrige tu verificación en Mi Perfil para poder postularte a estas ofertas.',
        actionLabel: 'Revisar Mi Perfil',
        onAction: _openProfileScreen,
      );
    }

    if (!isVerified || !caregiver.hasStripeAccount) {
      final detail = missingDocs.isNotEmpty
          ? 'Te falta completar: ${missingDocs.join(" • ")}. Puedes ver todas las ofertas mientras tanto.'
          : 'Tu perfil está en revisión (<24h). En cuanto sea aprobado podrás postularte.';
      return _buildInfoBanner(
        icon: missingDocs.isNotEmpty ? Icons.assignment_late_outlined : Icons.hourglass_top_rounded,
        color: missingDocs.isNotEmpty ? Colors.orange.shade900 : Colors.blue.shade800,
        bgColor: missingDocs.isNotEmpty ? Colors.orange.shade50 : Colors.blue.shade50,
        borderColor: missingDocs.isNotEmpty ? Colors.orange.shade300 : Colors.blue.shade200,
        title: missingDocs.isNotEmpty ? 'Completa tu perfil para postularte' : 'Perfil en revisión',
        message: detail,
        actionLabel: missingDocs.isNotEmpty ? 'Completar Mi Perfil' : null,
        onAction: missingDocs.isNotEmpty ? _openProfileScreen : null,
      );
    }

    return null;
  }

  Widget _buildInfoBanner({
    required IconData icon,
    required Color color,
    required Color bgColor,
    required Color borderColor,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: TextStyle(fontSize: 13, color: color, height: 1.35),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: borderColor, width: 1.4),
                  backgroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: onAction,
                icon: const Icon(Icons.person_outline_rounded, size: 18),
                label: Text(actionLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      avatar: Icon(
        icon,
        size: 16,
        color: selected ? Colors.white : AppTheme.primary,
      ),
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      showCheckmark: false,
      selectedColor: AppTheme.primary,
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? AppTheme.primary : AppTheme.borderSubtle),
      labelStyle: TextStyle(
        color: selected ? Colors.white : AppTheme.darkSlate,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _buildOfferCard({
    required JobOffer offer,
    required JobApplication? application,
    required double? distanceKm,
    required bool isApplicationsTab,
  }) {
    final effectiveHourlyRate = application?.proposedPrice ?? offer.pricePerHour;
    final estimatedNet = FirestoreStatsRepository.estimateOfferNetTotal(
      totalHours: offer.totalHours,
      hourlyRate: effectiveHourlyRate,
      urgencyBonusRate: offer.urgencyBonusRate,
    );
    final statusBadge = _buildStatusBadge(offer, application, isApplicationsTab);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: AppTheme.modernCardDecoration(radius: 20),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _openOfferDetail(offer),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ?statusBadge,
                    if (offer.isUrgent)
                      _buildTagPill(
                        label: '⚡ Urgente • Menos comisión',
                        bgColor: Colors.orange.shade50,
                        textColor: Colors.orange.shade900,
                        borderColor: Colors.orange.shade300,
                      ),
                    if (distanceKm != null)
                      _buildTagPill(
                        label: '📍 A ${distanceKm.toStringAsFixed(1)} km',
                        bgColor: AppTheme.primarySurface,
                        textColor: AppTheme.primary,
                        borderColor: AppTheme.primary.withValues(alpha: 0.25),
                      ),
                  ],
                ),
                if (statusBadge != null || offer.isUrgent || distanceKm != null) const SizedBox(height: 10),
                Text(
                  offer.familyLabel,
                  style: const TextStyle(color: AppTheme.slateMuted, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  offer.title,
                  style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800, color: AppTheme.darkSlate),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 15, color: AppTheme.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _formatOfferSchedule(offer),
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppTheme.darkSlate),
                      ),
                    ),
                  ],
                ),
                if (offer.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    offer.description.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, color: AppTheme.slateMuted, height: 1.35),
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.primarySurface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            application != null ? 'Tu propuesta' : 'Tarifa ofrecida',
                            style: const TextStyle(fontSize: 11.5, color: AppTheme.slateMuted, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${effectiveHourlyRate.toStringAsFixed(2)} €/h',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppTheme.primary),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text(
                            'Ganancia neta est.',
                            style: TextStyle(fontSize: 11.5, color: AppTheme.slateMuted, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '~${estimatedNet.toStringAsFixed(2)} €',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.secondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget? _buildStatusBadge(JobOffer offer, JobApplication? application, bool isApplicationsTab) {
    if (application == null) return null;

    if (application.status == JobApplicationStatus.accepted) {
      return _buildTagPill(
        label: '🎉 ¡Te eligieron!',
        bgColor: Colors.green.shade50,
        textColor: Colors.green.shade800,
        borderColor: Colors.green.shade300,
      );
    }

    if (application.status == JobApplicationStatus.rejected) {
      return _buildTagPill(
        label: 'No seleccionada',
        bgColor: Colors.grey.shade100,
        textColor: Colors.grey.shade700,
        borderColor: Colors.grey.shade300,
      );
    }

    if (offer.status == JobOfferStatus.cancelled) {
      return _buildTagPill(
        label: 'Oferta retirada',
        bgColor: Colors.red.shade50,
        textColor: Colors.red.shade700,
        borderColor: Colors.red.shade200,
      );
    }

    if (offer.status != JobOfferStatus.open) {
      return _buildTagPill(
        label: 'Cerrada',
        bgColor: Colors.grey.shade100,
        textColor: Colors.grey.shade700,
        borderColor: Colors.grey.shade300,
      );
    }

    if (offer.isExpired) {
      return _buildTagPill(
        label: 'Fecha pasada',
        bgColor: Colors.grey.shade100,
        textColor: Colors.grey.shade700,
        borderColor: Colors.grey.shade300,
      );
    }

    return _buildTagPill(
      label: isApplicationsTab ? '⏳ Esperando respuesta' : '✓ Solicitada',
      bgColor: Colors.teal.shade50,
      textColor: Colors.teal.shade800,
      borderColor: Colors.teal.shade300,
    );
  }

  Widget _buildTagPill({
    required String label,
    required Color bgColor,
    required Color textColor,
    required Color borderColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildEmptyAvailableState({required double maxDistance, required bool hasLocation}) {
    final isUrgentFilter = _selectedFilter == _CaregiverOfferFilter.urgentOnly;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(color: AppTheme.primarySurface, shape: BoxShape.circle),
              child: Icon(
                isUrgentFilter ? Icons.flash_off_rounded : Icons.search_off_rounded,
                size: 42,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              isUrgentFilter ? 'No hay ofertas urgentes ahora' : 'No hay ofertas disponibles cerca',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppTheme.darkSlate),
            ),
            const SizedBox(height: 8),
            Text(
              isUrgentFilter
                  ? 'Prueba a ver todas las ofertas abiertas en tu zona.'
                  : hasLocation
                      ? 'Ahora mismo no hay ofertas abiertas en un radio de ${maxDistance.round()} km. Puedes actualizar o ampliar tu distancia máxima en Mi Perfil.'
                      : 'Activa tu ubicación o añade tu dirección en Mi Perfil para ver ofertas cercanas.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppTheme.slateMuted, height: 1.4),
            ),
            const SizedBox(height: 20),
            if (isUrgentFilter)
              FilledButton.icon(
                onPressed: () => setState(() => _selectedFilter = _CaregiverOfferFilter.all),
                icon: const Icon(Icons.list_alt_rounded),
                label: const Text('Ver todas las ofertas'),
              )
            else ...[
              FilledButton.icon(
                onPressed: _handleRefresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Buscar de nuevo'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _openProfileScreen,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('Ajustar zona y radio en Mi Perfil'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 46, color: Colors.red.shade400),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.darkSlate),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _handleRefresh,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }
}
