import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../domain/entities/subscription_status.dart';
import '../../domain/repositories/i_subscription_repository.dart';
import '../../infrastructure/services/revenue_cat_service.dart';
import '../../../../core/constants/app_constants.dart';

// Events
abstract class SubscriptionEvent extends Equatable {
  const SubscriptionEvent();
  @override
  List<Object?> get props => [];
}

class SubscriptionCheckRequested extends SubscriptionEvent {
  const SubscriptionCheckRequested();
}

class SubscriptionPurchaseRequested extends SubscriptionEvent {
  const SubscriptionPurchaseRequested({required this.productId});
  final String productId;
  @override
  List<Object?> get props => [productId];
}

class SubscriptionRestoreRequested extends SubscriptionEvent {
  const SubscriptionRestoreRequested();
}

class SubscriptionTrialStartRequested extends SubscriptionEvent {
  const SubscriptionTrialStartRequested();
}

// States
abstract class SubscriptionState extends Equatable {
  const SubscriptionState();
  @override
  List<Object?> get props => [];
}

class SubscriptionInitial extends SubscriptionState {
  const SubscriptionInitial();
}

class SubscriptionLoading extends SubscriptionState {
  const SubscriptionLoading();
}

class SubscriptionLoaded extends SubscriptionState {
  const SubscriptionLoaded({
    required this.status,
    this.products = const [],
  });
  final SubscriptionStatus status;
  final List<SubscriptionProduct> products;
  @override
  List<Object?> get props => [status, products];
}

class SubscriptionPurchasing extends SubscriptionState {
  const SubscriptionPurchasing({required this.productId});
  final String productId;
  @override
  List<Object?> get props => [productId];
}

class SubscriptionPurchaseCancelled extends SubscriptionState {
  const SubscriptionPurchaseCancelled();
}

class SubscriptionError extends SubscriptionState {
  const SubscriptionError({required this.message});
  final String message;
  @override
  List<Object?> get props => [message];
}

@injectable
class SubscriptionBloc extends Bloc<SubscriptionEvent, SubscriptionState> {
  SubscriptionBloc(this._repository) : super(const SubscriptionInitial()) {
    on<SubscriptionCheckRequested>(_onCheckRequested);
    on<SubscriptionPurchaseRequested>(_onPurchaseRequested);
    on<SubscriptionRestoreRequested>(_onRestoreRequested);
    on<SubscriptionTrialStartRequested>(_onTrialStartRequested);
  }

  final ISubscriptionRepository _repository;

  Future<void> _onCheckRequested(
    SubscriptionCheckRequested event,
    Emitter<SubscriptionState> emit,
  ) async {
    emit(const SubscriptionLoading());
    try {
      final status = await _repository.getEntitlement();
      final products = await _repository.getAvailableProducts();
      emit(SubscriptionLoaded(status: status, products: products));
    } catch (e) {
      emit(SubscriptionError(message: e.toString()));
    }
  }

  Future<void> _onPurchaseRequested(
    SubscriptionPurchaseRequested event,
    Emitter<SubscriptionState> emit,
  ) async {
    emit(SubscriptionPurchasing(productId: event.productId));
    try {
      final status = await _repository.purchase(event.productId);
      final products = await _repository.getAvailableProducts();
      emit(SubscriptionLoaded(status: status, products: products));
    } on PurchaseCancelledException {
      emit(const SubscriptionPurchaseCancelled());
      // Re-check current status after cancel
      add(const SubscriptionCheckRequested());
    } catch (e) {
      emit(SubscriptionError(message: e.toString()));
    }
  }

  Future<void> _onRestoreRequested(
    SubscriptionRestoreRequested event,
    Emitter<SubscriptionState> emit,
  ) async {
    emit(const SubscriptionLoading());
    try {
      final status = await _repository.restorePurchases();
      final products = await _repository.getAvailableProducts();
      emit(SubscriptionLoaded(status: status, products: products));
    } catch (e) {
      emit(SubscriptionError(message: e.toString()));
    }
  }

  Future<void> _onTrialStartRequested(
    SubscriptionTrialStartRequested event,
    Emitter<SubscriptionState> emit,
  ) async {
    emit(const SubscriptionLoading());
    try {
      final status = await _repository.startTrial();
      emit(SubscriptionLoaded(status: status));
    } catch (e) {
      emit(SubscriptionError(message: e.toString()));
    }
  }
}
