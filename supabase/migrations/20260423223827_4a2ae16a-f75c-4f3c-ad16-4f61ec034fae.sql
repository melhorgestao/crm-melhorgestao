
-- 1) RPC SECURITY DEFINER para listar sócios contornando RLS de perfis_usuario
CREATE OR REPLACE FUNCTION public.listar_socios()
RETURNS TABLE (socio_key text, nome text)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT UPPER(p.socio_key)::text AS socio_key, p.nome
  FROM public.perfis_usuario p
  WHERE p.tipo_usuario = 'admin'
    AND p.socio_key IS NOT NULL
    AND p.nome IS NOT NULL
  ORDER BY p.nome;
$$;

GRANT EXECUTE ON FUNCTION public.listar_socios() TO authenticated;

-- 2) Reverter 6 pedidos contaminados (API SuperFrete diz "released" mas banco diz "postado")
UPDATE public.pedidos
SET status_pedido = 'aguardando_rastreio'
WHERE id IN (
  'c09bc10b-4196-4df6-8fc7-2c2d9d924e63', -- #34
  '0a4e84a8-91bb-46b4-867f-04ad4478ed3c', -- #31
  '0c83456e-b4aa-4153-8367-b5e8e343f2fd', -- #27
  '2befd036-8812-43df-aa75-d56bdd216506', -- #25
  'cec580ee-6d3c-48ce-9c3d-b25248d7028a', -- #15
  '9e55cb5a-4257-42c6-91a3-8cb14e9fd132'  -- #12
)
AND status_pedido = 'postado';

-- 3) Reverter 2 pedidos travados como "entregue" indevidamente (#29 e #26 Vinicius)
UPDATE public.pedidos
SET status_pedido = 'aguardando_rastreio'
WHERE id IN (
  '0b3b761d-f5b8-4bc0-8fc3-971a3a7a0e14', -- #29
  '10a55370-253c-4122-a584-ab106cbb6238'  -- #26 Vinicius
)
AND status_pedido = 'entregue';

-- 4) Auditoria
INSERT INTO public.log_atividades (usuario, acao, tabela_afetada, registro_id, detalhe)
SELECT
  'Sistema (Reversão Sync)',
  'Status revertido para aguardando_rastreio (mapeamento SuperFrete corrigido)',
  'pedidos',
  id,
  'Status anterior divergia da API SuperFrete (released/entregue indevido). Card retorna para Logística.'
FROM public.pedidos
WHERE id IN (
  'c09bc10b-4196-4df6-8fc7-2c2d9d924e63',
  '0a4e84a8-91bb-46b4-867f-04ad4478ed3c',
  '0c83456e-b4aa-4153-8367-b5e8e343f2fd',
  '2befd036-8812-43df-aa75-d56bdd216506',
  'cec580ee-6d3c-48ce-9c3d-b25248d7028a',
  '9e55cb5a-4257-42c6-91a3-8cb14e9fd132',
  '0b3b761d-f5b8-4bc0-8fc3-971a3a7a0e14',
  '10a55370-253c-4122-a584-ab106cbb6238'
);
