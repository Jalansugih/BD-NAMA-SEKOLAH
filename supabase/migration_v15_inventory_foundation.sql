-- BILLINGFLOW V15 — PRODUCT & INVENTORY FOUNDATION
-- Run after V14. Non-destructive and tenant-isolated.

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS track_inventory BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS cost_price NUMERIC(18,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS min_stock NUMERIC(18,4) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS stock_qty NUMERIC(18,4) NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS public.inventory_movements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE RESTRICT,
  movement_date DATE NOT NULL DEFAULT CURRENT_DATE,
  movement_type VARCHAR(30) NOT NULL CHECK (movement_type IN ('OPENING','PURCHASE','SALE','ADJUSTMENT_IN','ADJUSTMENT_OUT','RETURN_IN','RETURN_OUT')),
  quantity NUMERIC(18,4) NOT NULL CHECK (quantity <> 0),
  unit_cost NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (unit_cost >= 0),
  reference_type VARCHAR(50), reference_id UUID, notes TEXT,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_inventory_movements_org_product_date ON public.inventory_movements(organization_id,product_id,movement_date DESC);
ALTER TABLE public.inventory_movements ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "inventory movements tenant read" ON public.inventory_movements;
CREATE POLICY "inventory movements tenant read" ON public.inventory_movements FOR SELECT USING (organization_id=public.get_auth_org_id());

CREATE OR REPLACE FUNCTION public.adjust_product_stock_atomic(p_product_id UUID,p_delta NUMERIC,p_movement_type TEXT DEFAULT NULL,p_notes TEXT DEFAULT NULL,p_movement_date DATE DEFAULT CURRENT_DATE)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_org UUID:=public.get_auth_org_id(); v_product RECORD; v_type TEXT; v_movement UUID;
BEGIN
  IF v_org IS NULL THEN RAISE EXCEPTION 'Organisasi tidak ditemukan'; END IF;
  IF p_delta IS NULL OR p_delta=0 THEN RAISE EXCEPTION 'Perubahan stok tidak boleh 0'; END IF;
  SELECT * INTO v_product FROM public.products WHERE id=p_product_id AND organization_id=v_org FOR UPDATE;
  IF v_product.id IS NULL THEN RAISE EXCEPTION 'Produk tidak ditemukan'; END IF;
  IF NOT v_product.track_inventory THEN RAISE EXCEPTION 'Produk ini tidak menggunakan pelacakan persediaan'; END IF;
  IF v_product.stock_qty+p_delta < 0 THEN RAISE EXCEPTION 'Stok tidak boleh negatif'; END IF;
  v_type:=COALESCE(p_movement_type,CASE WHEN p_delta>0 THEN 'ADJUSTMENT_IN' ELSE 'ADJUSTMENT_OUT' END);
  INSERT INTO public.inventory_movements(organization_id,product_id,movement_date,movement_type,quantity,unit_cost,notes,created_by) VALUES(v_org,p_product_id,p_movement_date,v_type,p_delta,COALESCE(v_product.cost_price,0),p_notes,auth.uid()) RETURNING id INTO v_movement;
  UPDATE public.products SET stock_qty=stock_qty+p_delta,updated_at=NOW() WHERE id=p_product_id;
  RETURN jsonb_build_object('movement_id',v_movement,'product_id',p_product_id,'stock_qty',v_product.stock_qty+p_delta,'delta',p_delta);
END; $$;
REVOKE ALL ON FUNCTION public.adjust_product_stock_atomic(UUID,NUMERIC,TEXT,TEXT,DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.adjust_product_stock_atomic(UUID,NUMERIC,TEXT,TEXT,DATE) TO authenticated;
