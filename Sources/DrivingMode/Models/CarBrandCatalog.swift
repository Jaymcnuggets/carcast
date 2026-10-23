//
//  CarBrandCatalog.swift
//  DrivingMode
//
//  Authentic 114 OEM Car Brands Catalog.
//

import Foundation
import SwiftUI

public struct CarBrand: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let label: String?
    public let title: String
    public let zh: String?

    public var displayName: String {
        return title
    }

    public var oemLabel: String {
        return label ?? title.uppercased()
    }
}

public final class CarBrandCatalog: @unchecked Sendable {
    public static let shared = CarBrandCatalog()

    public private(set) var brands: [CarBrand] = []
    private var brandMap: [String: CarBrand] = [:]

    private init() {
        loadBrands()
    }

    private func loadBrands() {
        // Try loading from Bundle.main or Bundle.module
        var data: Data?

        if let url = Bundle.main.url(forResource: "logos", withExtension: "json") {
            data = try? Data(contentsOf: url)
        } else if let url = Bundle.main.url(forResource: "Resources/logos", withExtension: "json") {
            data = try? Data(contentsOf: url)
        }

        if let data = data, let decoded = try? JSONDecoder().decode([CarBrand].self, from: data) {
            self.brands = decoded
        } else {
            // Fallback canonical list if file not yet bundled in tests
            self.brands = Self.defaultBrands
        }

        for brand in self.brands {
            brandMap[brand.id.lowercased()] = brand
        }
    }

    public func brand(for id: String) -> CarBrand? {
        return brandMap[id.lowercased()]
    }

    public func logoImageName(for brandId: String, size: Int = 180) -> String {
        let canonicalSize = [120, 180, 256].contains(size) ? size : 180
        return "\(brandId)_oem_\(canonicalSize)"
    }

    #if canImport(UIKit)
    public func logoImage(for brandId: String, size: Int = 180) -> UIImage? {
        let name = logoImageName(for: brandId, size: size)
        if let img = UIImage(named: name) { return img }
        if let url = Bundle.main.url(forResource: name, withExtension: "png") {
            return UIImage(contentsOfFile: url.path)
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Logos") {
            return UIImage(contentsOfFile: url.path)
        }
        return nil
    }
    #endif

    public static let defaultBrands: [CarBrand] = [
        CarBrand(id: "lexus", label: "LEXUS", title: "Lexus", zh: "雷克萨斯"),
        CarBrand(id: "tesla", label: "TESLA", title: "Tesla", zh: "特斯拉"),
        CarBrand(id: "bmw", label: "BMW", title: "BMW", zh: "宝马"),
        CarBrand(id: "porsche", label: "PORSCHE", title: "Porsche", zh: "保时捷"),
        CarBrand(id: "audi", label: "AUDI", title: "Audi", zh: "奥迪"),
        CarBrand(id: "mercedes", label: "MERCEDES", title: "Mercedes-Benz", zh: "梅赛德斯-奔驰"),
        CarBrand(id: "ferrari", label: "FERRARI", title: "Ferrari", zh: "法拉利"),
        CarBrand(id: "lamborghini", label: "LAMBORGHINI", title: "Lamborghini", zh: "兰博基尼"),
        CarBrand(id: "ford", label: "FORD", title: "Ford", zh: "福特"),
        CarBrand(id: "toyota", label: "TOYOTA", title: "Toyota", zh: "丰田"),
        CarBrand(id: "honda", label: "HONDA", title: "Honda", zh: "本田"),
        CarBrand(id: "volkswagen", label: "VOLKSWAGEN", title: "Volkswagen", zh: "大众"),
        CarBrand(id: "volvo", label: "VOLVO", title: "Volvo", zh: "沃尔沃"),
        CarBrand(id: "chevrolet", label: "CHEVROLET", title: "Chevrolet", zh: "雪佛兰"),
        CarBrand(id: "hyundai", label: "HYUNDAI", title: "Hyundai", zh: "现代"),
        CarBrand(id: "kia", label: "KIA", title: "Kia", zh: "起亚"),
        CarBrand(id: "nissan", label: "NISSAN", title: "Nissan", zh: "日产"),
        CarBrand(id: "subaru", label: "SUBARU", title: "Subaru", zh: "斯巴鲁"),
        CarBrand(id: "mazda", label: "MAZDA", title: "Mazda", zh: "马自达"),
        CarBrand(id: "jeep", label: "JEEP", title: "Jeep", zh: "吉普"),
        CarBrand(id: "cadillac", label: "CADILLAC", title: "Cadillac", zh: "凯迪拉克"),
        CarBrand(id: "alfa_romeo", label: "ALFA ROMEO", title: "Alfa Romeo", zh: "阿尔法·罗密欧"),
        CarBrand(id: "aston_martin", label: "ASTON MARTIN", title: "Aston Martin", zh: "阿斯顿·马丁"),
        CarBrand(id: "bentley", label: "BENTLEY", title: "Bentley", zh: "宾利"),
        CarBrand(id: "bugatti", label: "BUGATTI", title: "Bugatti", zh: "布加迪"),
        CarBrand(id: "byd", label: "BYD", title: "BYD", zh: "比亚迪"),
        CarBrand(id: "xiaomi", label: "XIAOMI", title: "Xiaomi", zh: "小米"),
        CarBrand(id: "xpeng", label: "XPENG", title: "XPeng", zh: "小鹏"),
        CarBrand(id: "zeekr", label: "ZEEKR", title: "Zeekr", zh: "极氪"),
        CarBrand(id: "rivian", label: "RIVIAN", title: "Rivian", zh: "Rivian"),
        CarBrand(id: "polestar", label: "POLESTAR", title: "Polestar", zh: "极星"),
        CarBrand(id: "land_rover", label: "LAND ROVER", title: "Land Rover", zh: "路虎"),
        CarBrand(id: "maserati", label: "MASERATI", title: "Maserati", zh: "玛莎拉蒂"),
        CarBrand(id: "mclaren", label: "MCLAREN", title: "McLaren", zh: "迈凯伦"),
        CarBrand(id: "bicycle", label: "Bike", title: "Bicycle", zh: "自行车"),
        CarBrand(id: "motorcycle", label: "Moto", title: "Motorcycle", zh: "摩托车"),
        CarBrand(id: "car", label: "Car", title: "Car", zh: "汽车")
    ]
}
