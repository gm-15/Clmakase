package com.oliveyoung.sale.config;

import com.oliveyoung.sale.domain.Product;
import com.oliveyoung.sale.repository.ProductRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.CommandLineRunner;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.util.List;

/**
 * 개발/시연용 초기 데이터 생성
 */
@Slf4j
@Component
@Profile("local | prod") // 로컬 및 prod 환경에서 실행 (이미 데이터 있으면 스킵)
@RequiredArgsConstructor
public class DataInitializer implements CommandLineRunner {

    private final ProductRepository productRepository;

    @Override
    public void run(String... args) {
        if (productRepository.count() > 0) {
            log.info("이미 데이터가 존재합니다. 초기화 스킵.");
            return;
        }

        List<Product> products = List.of(
                Product.builder()
                        .name("컬러그램 글리터 틴트")
                        .description("촉촉한 발림성과 영롱한 글리터가 특징인 틴트")
                        .originalPrice(new BigDecimal("18000"))
                        .discountRate(30)
                        .stock(100)
                        .imageUrl("https://via.placeholder.com/300x300/FFB6C1/000000?text=Tint")
                        .category("립메이크업")
                        .build(),

                Product.builder()
                        .name("라운드랩 1025 독도 토너")
                        .description("저자극 약산성 토너, 피부 진정에 효과적")
                        .originalPrice(new BigDecimal("23000"))
                        .discountRate(35)
                        .stock(150)
                        .imageUrl("https://via.placeholder.com/300x300/87CEEB/000000?text=Toner")
                        .category("스킨케어")
                        .build(),

                Product.builder()
                        .name("이니스프리 노세범 파우더")
                        .description("피지 컨트롤에 탁월한 미네랄 파우더")
                        .originalPrice(new BigDecimal("12000"))
                        .discountRate(25)
                        .stock(200)
                        .imageUrl("https://via.placeholder.com/300x300/F0E68C/000000?text=Powder")
                        .category("베이스메이크업")
                        .build(),

                Product.builder()
                        .name("토리든 다이브인 세럼")
                        .description("히알루론산 5종 함유 수분 집중 세럼")
                        .originalPrice(new BigDecimal("28000"))
                        .discountRate(40)
                        .stock(80)
                        .imageUrl("https://via.placeholder.com/300x300/98FB98/000000?text=Serum")
                        .category("스킨케어")
                        .build(),

                Product.builder()
                        .name("클리오 킬커버 파운데이션")
                        .description("강력한 커버력의 롱래스팅 파운데이션")
                        .originalPrice(new BigDecimal("32000"))
                        .discountRate(30)
                        .stock(120)
                        .imageUrl("https://via.placeholder.com/300x300/DDA0DD/000000?text=Foundation")
                        .category("베이스메이크업")
                        .build(),

                Product.builder()
                        .name("에뛰드 플레이컬러 아이팔레트")
                        .description("데일리부터 포인트까지, 10컬러 아이 팔레트")
                        .originalPrice(new BigDecimal("25000"))
                        .discountRate(35)
                        .stock(90)
                        .imageUrl("https://via.placeholder.com/300x300/FFD700/000000?text=Palette")
                        .category("아이메이크업")
                        .build(),

                Product.builder()
                        .name("아이소이 불가리안 로즈 미스트")
                        .description("천연 장미 성분의 수분 미스트")
                        .originalPrice(new BigDecimal("19000"))
                        .discountRate(20)
                        .stock(180)
                        .imageUrl("https://via.placeholder.com/300x300/FFC0CB/000000?text=Mist")
                        .category("스킨케어")
                        .build(),

                Product.builder()
                        .name("메이크프렘 세이프미 선크림")
                        .description("민감성 피부를 위한 저자극 선크림 SPF50+")
                        .originalPrice(new BigDecimal("21000"))
                        .discountRate(30)
                        .stock(160)
                        .imageUrl("https://via.placeholder.com/300x300/FFFACD/000000?text=Sunscreen")
                        .category("선케어")
                        .build()
        );

        productRepository.saveAll(products);
        log.info("✅ 초기 상품 데이터 {}개 생성 완료", products.size());
    }
}
