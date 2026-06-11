enum ShopCategory {
  food,
  retail,
  services,
  transit,
  washroom,
  hotel,
  health,
  entertainment,
}

extension ShopCategoryExt on ShopCategory {
  String get label {
    switch (this) {
      case ShopCategory.food:
        return 'Food & Dining';
      case ShopCategory.retail:
        return 'Retail & Shopping';
      case ShopCategory.services:
        return 'Services';
      case ShopCategory.transit:
        return 'Transit';
      case ShopCategory.washroom:
        return 'Washroom';
      case ShopCategory.hotel:
        return 'Hotel';
      case ShopCategory.health:
        return 'Health & Wellness';
      case ShopCategory.entertainment:
        return 'Entertainment';
    }
  }

  String get icon {
    switch (this) {
      case ShopCategory.food:
        return 'restaurant';
      case ShopCategory.retail:
        return 'shopping_bag';
      case ShopCategory.services:
        return 'business_center';
      case ShopCategory.transit:
        return 'train';
      case ShopCategory.washroom:
        return 'wc';
      case ShopCategory.hotel:
        return 'hotel';
      case ShopCategory.health:
        return 'local_hospital';
      case ShopCategory.entertainment:
        return 'theaters';
    }
  }
}

class Shop {
  final String id;
  final String name;
  final String buildingId;
  final ShopCategory category;
  final String hours;
  final String phone;
  final String website;
  final String description;

  const Shop({
    required this.id,
    required this.name,
    required this.buildingId,
    required this.category,
    this.hours = '',
    this.phone = '',
    this.website = '',
    this.description = '',
  });

  factory Shop.fromJson(Map<String, dynamic> json) => Shop(
        id: json['id'] as String,
        name: json['name'] as String,
        buildingId: json['buildingId'] as String,
        category: ShopCategory.values.firstWhere(
          (e) => e.name == json['category'],
          orElse: () => ShopCategory.services,
        ),
        hours: json['hours'] as String? ?? '',
        phone: json['phone'] as String? ?? '',
        website: json['website'] as String? ?? '',
        description: json['description'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'buildingId': buildingId,
        'category': category.name,
        'hours': hours,
        'phone': phone,
        'website': website,
        'description': description,
      };
}
