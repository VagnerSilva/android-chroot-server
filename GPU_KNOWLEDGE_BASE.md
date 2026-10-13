# Base de conhecimento GPU

Fonte canônica para estado, medições e decisões de GPU deste repositório. Registre cada medição com dispositivo, caminho de renderização, ferramenta e resultado. `docs/gpu.md` e `docs/gpu.pt.md` descrevem o uso diário; `KNOWN_ISSUES.md` mantém histórico detalhado.

## Decisão atual

**Conclusão atual: sim, é possível atualizar para Mesa 26+ pelo fluxo controlado de build, ensaio e promoção; Mesa 25.1.2 continua em produção até a aprovação explícita do candidato.** O candidato Mesa 26.2.4 já ensaiado não demonstrou OpenGL 4.x e a validação GLX/desenho ficou incompleta. Atualizar Mesa não equivale a atualizar o driver Vulkan nem eleva, por si só, a versão GL. Nos stacks atuais, GL 4.x real não foi obtido; para avançar além desse limite, o próximo trabalho é atualizar ou substituir o driver GPU e repetir a qualificação, uma mudança mais complexa ainda não testada aqui. A medição Vulkan 1.4 do Poco pertence ao caminho PanVK e não altera o resultado Vulkan do ICD ARM proprietário no Moto G86.

O Moto G86 (Mali-G615 MC2) e o Poco X6 Pro (Mali-G615 MC6) usam a mesma arquitetura Mali-G615; MC2 e MC6 indicam, respectivamente, 2 e 6 núcleos de processamento, não arquiteturas ou conjuntos de recursos gráficos diferentes. A contagem de núcleos afeta processamento/desempenho, não constitui por si só evidência de diferença no suporte a APIs. Nos stacks testados, GL 4.x não foi obtido: Mesa 25.1.2/Zink no G86 reportou 3.1; o ensaio isolado Mesa 26.2.4/Zink no G86 também reportou 3.1; e Zink/PanVK no Poco reportou 3.3, com pedidos 4.x falhando na criação de contexto. Esses resultados descrevem software e configurações testadas; não demonstram impossibilidade para outra build ou driver.

### Mesa 26: resultado e caminho de avaliação

É importante não transformar “o candidato ainda não está aprovado para produção” em “não é possível atualizar Mesa”. O repositório registra tanto um build de Mesa 26.2.4 para ARM64 quanto ensaios reais em cópia isolada. O resultado até aqui é parcial e não atende ao objetivo GL 4.6:

| Ensaio | O que foi testado | Resultado documentado | O que isso demonstra / não demonstra |
|---|---|---|---|
| Moto G86, baseline Mesa 25.1.2 | Zink sobre Vulkan Mali ARM proprietário; EGL/GL reportado no uso atual | GL desktop 3.1; ICD Vulkan API 1.3.247; avisos Zink para `logicOp`, `fillModeNonSolid` e `shaderClipDistance` | Baseline funcional no nível observado; não demonstra GL 4.x |
| Moto G86, Mesa 26.2.4 em imagem isolada | Candidato `1:26.2.4-1`; versão final corrigida inicializou `vulkaninfo --summary` e EGL surfaceless; EGL identificou Zink/Mali G615 e GL 3.1 | Igualou, sem superar, o nível GL 3.1 da baseline; permaneceu aviso de `logicOp` ausente | Demonstra que esse candidato consegue inicializar EGL/Zink no ensaio final; não demonstra GL 4.x nem ganho sobre Mesa 25 |
| Mesmo ensaio, `vkcube` | Vulkan via wrapper `gpu-vulkan-run`, com overlay Mali | Retorno 0 no teste registrado | Demonstra execução do caminho Vulkan proprietário usado pelo wrapper; não é teste de renderização GL por Zink |
| Mesmo ensaio, GLX/desenho | Dependia do socket Termux:X11 `:0` | Socket indisponível na validação final; `glxinfo` e desenho sustentado não foram validados | Gate incompleta; a ausência do display não deve ser contada como aprovação nem como falha do driver |
| Poco X6 Pro, PanVK/Zink | Mesa 26.1.6 no renderer GL; PanVK desconhece `0xa8671030` e usa defaults conservadores | GL máximo observado 3.3; GL 4.0–4.6 falha com `EGL_BAD_ALLOC`; features Vulkan reportadas incluem `geometryShader=no` e `tessellationShader=no` | Limite medido neste caminho PanVK; não é o teste do pacote Mesa 26.2.4 no G86 nem prova de impossibilidade para outro driver/build |

O fluxo de atualização/qualificação registrado no repositório é:

1. **Build do candidato ARM64:** `host/build-mesa26-android-mali-wsl.sh` usa a branch local `mesa-26.2.4`, verifica `VERSION=26.2.4`, cria/reusa worktree destacado e aplica os patches previstos. O build habilita softpipe+Zink, X11/Wayland e GLX DRI, valida opções Meson e empacota um tarball. Pelo próprio script, isso não instala no host nem no aparelho/rootfs.
2. **Ensaio em dispositivo:** `device/setup/test-mesa-26.sh` exige root e imagem principal existente; cria `rootfs-mesa26-test.img` como cópia isolada, recusa sobrescrever a cópia existente por padrão, registra versão/configuração/log e sincroniza/instala Mesa 26 somente nessa cópia. `KNOWN_ISSUES.md` exige container principal parado e espaço para a segunda imagem. A cópia e os logs são retidos para inspeção; remoção é manual.
3. **Proveniência entre build e ensaio:** o script de ensaio obtém a versão candidata com `pacman -Si mesa` e instala com `pacman -S` dentro da cópia. Ele não consome automaticamente o tarball gerado pelo script host. Portanto, um tarball customizado e um pacote do repositório são candidatos diferentes até que sua identidade/instalação seja explicitamente comprovada no log.
4. **Gates runtime:** o script tenta `vulkaninfo --summary` e `eglinfo -p surfaceless`; com Termux:X11 `:0` disponível, também executa `glxinfo -B` e `vkcube --wsi xcb --c 120`. Falha em runtime resulta em NO-GO; ferramenta/display ausente resulta em INCONCLUSIVO; sucesso completo resulta apenas em **GO para revisão humana**, não em promoção automática.
5. **Promoção:** só depois da revisão das evidências e autorização explícita pode-se decidir sobre produção. O script de teste protege a imagem principal e não faz essa promoção. O histórico diz que a Fase 5 foi fechada, sem novos testes Mesa 26 planejados naquela fase; isso descreve o encerramento da fase, não uma impossibilidade técnica de reabrir uma avaliação seguindo os gates.

**Conclusão de atualização:** atualizar para Mesa 26+ é possível; o caminho de build e teste isolado existe e deve ser seguido antes de qualquer promoção. O candidato 26.2.4 atual ainda não está qualificado para produção porque faltam validação GLX e desenho sustentado, além da revisão/aprovação. Mesmo uma promoção futura de Mesa 26 não implicaria OpenGL 4.x: o ensaio atual no G86 permaneceu em GL 3.1. Para obter GL 4.x real, a análise atual aponta para trabalho no driver GPU; isso não foi executado nem há evidência suficiente para garantir qual versão/driver o habilitaria.

### Override GL 4.6: bypass seletivo

O override `MESA_GL_VERSION_OVERRIDE=4.6` com `MESA_GLSL_VERSION_OVERRIDE=460` é indicado na skill como bypass seletivo para aplicativos que apenas recusam iniciar por consultarem uma versão mínima e que não usem geometry/tessellation ou outros recursos não suportados. Ele altera a versão/linguagem reportada; não adiciona recursos ao driver nem transforma o renderer em GL 4.6 completo. Pode permitir que alguns aplicativos avancem além da checagem inicial, mas pode falhar na criação do contexto, compilação de shaders ou execução quando o aplicativo usar recursos ausentes. A skill não traz resultado de validação por aplicativo; cada uso deve ser tratado como experimento de compatibilidade e testado individualmente. Não usar o override para medir capabilities, anunciar conformidade GL 4.6 ou aprovar promoção de Mesa.

## Estado e evidências

### Medição via ADB nesta sessão

Dispositivo conectado: Moto G86 5G; SoC `MT6878`; GPU Mali-G615 MC2. A consulta ocorreu no container Artix ativo, sem instalar pacotes ou alterar arquivos do rootfs. Mesa 25.1.2 permaneceu como baseline; nenhum pacote foi instalado ou promovido.

| Interface / componente | Resultado observado | Interpretação |
|---|---|---|
| Vulkan ICD/dispositivo | `apiVersion=1.3.247`; driver ARM proprietário `44.1.0`; Mali-G615 MC2 | Vulkan 1.4 não demonstrado pelo driver |
| Vulkan instance/loader | `Vulkan Instance Version: 1.4.357` | Não confundir com `apiVersion` do dispositivo; não prova suporte Vulkan 1.4 no Mali |
| OpenGL desktop, Zink/GLX | Mesa 25.1.2; versão core e compatibility máxima reportada `3.1` | Não satisfaz `> 3.1` nem o objetivo OpenGL 4.6 |
| OpenGL desktop, softpipe/GLX | Mesa 25.1.2; core e compatibility `3.3`; renderer `softpipe` | Caminho CPU também não oferece OpenGL 4.x; não é renderização acelerada Mali |
| OpenGL ES nativo, ARM EGL | OpenGL ES 3.2; renderer Mali-G615 MC2 | Interface distinta de OpenGL desktop; não substitui o requisito GLX/OpenGL |
| Requisitos Vulkan para Zink | Avisos de ausência de `logicOp`, `fillModeNonSolid`, `shaderClipDistance` | Limitação observada no caminho Zink desta medição |
| ICD Vulkan ativo | `/usr/share/vulkan/icd.d/wrapper_icd.aarch64.json`, dispositivo Mali ARM proprietário | Não foi identificado ICD Mesa/lavapipe na pasta de ICD ativa; Vulkan software não foi avaliado |
| Mesa de produção | 25.1.2 | Manter como baseline |
| Candidato Mesa | 26.2.4 | Não promovido; histórico abaixo |

Origem da medição em 2026-10-12: `DISPLAY=:0 /data/linux/zink-run.sh glxinfo -B` reportou Zink/Mali OpenGL 3.1 e os avisos de features; `vulkaninfo --summary` via `/data/linux/gpu-vulkan-run.sh` reportou a versão da instância e `apiVersion` real do Mali; `glxinfo -B` executado no chroot com `LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=softpipe` reportou OpenGL 3.3 em CPU. A pasta ICD ativa continha somente `wrapper_icd.aarch64.json`. O WSL2 x86_64 não foi usado como substituto da GPU Android.

**Conclusão para o stack Mesa 25.1.2 atual neste aparelho:** NO-GO para OpenGL 4.x nos dois caminhos medidos (Zink/Mali 3.1; softpipe 3.3) e NO-GO para Vulkan 1.4 no Mali (ICD 1.3.247). A versão Vulkan 1.4.357 é do loader/instância, não da GPU. Isso não prova impossibilidade para outro ICD, driver ou build; Vulkan via software não foi avaliado e não há ICD Mesa software na pasta ativa. Não foi executado teste de desenho sustentado; OpenGL 4.6 não está validado.

### Medição PanVK/Zink — Poco X6 Pro / Dimensity 8300 / Mali-G615 MC6

Registro obtido por consulta no Poco X6 Pro, cuja GPU é Mali-G615 MC6 (6 núcleos de processamento). A enumeração Vulkan retorna `deviceID=0xa8671030` e `Mali unknown ... MC6`; PanVK não reconhece esse ID/variante e executa com defaults conservadores de Mali Valhall desconhecido. Portanto, G615 MC6 é a identificação do hardware do aparelho, enquanto “unknown” descreve o reconhecimento do driver. Não há base para reclassificar a GPU como G610. O Moto G86 usa a mesma arquitetura Mali-G615 em variante MC2 (2 núcleos); sua medição nesta base usa o driver ARM proprietário e Mesa 25.1.2, não PanVK/Zink. As medições convergem quanto à ausência de GL 4.x, mas os recursos Vulkan ausentes foram observados nos defaults do PanVK e não podem ser atribuídos ao hardware em geral nem ao ICD proprietário do Moto sem consulta independente nesse driver.

| Interface / componente | Resultado observado | Interpretação |
|---|---|---|
| Aparelho / GPU | Poco X6 Pro, Dimensity 8300; Mali-G615 MC6 (6 núcleos); Vulkan enumera `Mali unknown 0xa8671030 MC6`; tipo integrado | Mesma arquitetura G615 da variante MC2 do Moto G86; PanVK não reconhece o ID/variante e usa defaults conservadores |
| Vulkan dispositivo | API `1.4.352`; driver ID 20, `panvk`; `Mesa 26.2.0-devel`; fila GFX/compute/transfer (2 filas); heap local 5498 MB | API/driver enumerados no dispositivo PanVK; não é o resultado do ICD ARM proprietário do Moto G86 |
| Vulkan extensões | 22 extensões de instância e 168 de dispositivo | Enumerações integrais no registro-fonte abaixo |
| Vulkan features críticas | `geometryShader=no`, `tessellationShader=no`, `shaderFloat64=no`, `shaderClipDistance=no`, `shaderCullDistance=no`, `multiViewport=no`; `shaderInt64=yes`, `shaderFloat16=yes`, `shaderInt8=yes`, `descriptorIndexing=yes`, `bufferDeviceAddress=yes`, `dynamicRendering=yes`, `synchronization2=yes`, `timelineSemaphore=yes` | Ausência dos estágios de geometria/tesselação explica o limite observado de GL 3.3 neste caminho Zink |
| Outros recursos Vulkan | `logicOp=yes`, `fillModeNonSolid=yes`, `depthClamp=yes`, `multiDrawIndirect=yes`, `sampleRateShading=yes`; `sparseBinding=no` e todos os recursos sparse enumerados como `no` | Features conforme consulta; consultar o registro-fonte para a matriz completa Vulkan 1.0–1.4 |
| Desktop GL por Zink/PanVK | Mesa 26.1.6; renderer `zink Vulkan 1.4(Mali unknown 0xa8671030 MC6 (MESA_PANVK))`; máximo observado 3.3 core e compat | GL acelerado pelo caminho Zink sobre Vulkan/PanVK; a versão da string Vulkan no renderer não é uma medição independente de GL 4.x |
| GL 3.2 core solicitado | EGL surfaceless/configless, `EGL_MESA_configless_context`; com overrides `MESA_GL_VERSION_OVERRIDE=3.2` e `MESA_GLSL_VERSION_OVERRIDE=150`: GL 3.2 Core, GLSL 1.50, 215 extensões | Sem override, o pedido equivalente entrega GL 3.3 Core; conjunto de extensões igual (215) |
| Pedidos de GL 4.x | GL 4.0–4.6 core e GL 4.6 compat falharam com `EGL_BAD_ALLOC` (`0x3009`) | GL 4.x não está disponível/validado neste caminho; nenhum limite ou conjunto de extensões GL 4.5/4.6 foi obtido |
| GLES | OpenGL ES 3.1; pedido ES 3.2 falhou com `EGL_BAD_ALLOC` | Máximo observado neste caminho é GLES 3.1 |
| Limites GL relevantes | Textura 16384; textura 3D/cubemap e camadas array 65536; 16 atributos vertex; 8 draw buffers/color attachments; 8 samples; geometry output vertices 0; patch vertices 0; tessellation limits 0 | Zeros de geometry/tessellation são coerentes com as features Vulkan ausentes; a tabela integral tem os demais limites consultados |

A medição GL usou EGL surfaceless, pois não há configuração EGL anunciando `EGL_OPENGL_BIT`; contexts desktop foram criados configless. O caminho GL é Zink (`GALLIUM_DRIVER=zink`) sobre PanVK, não um driver GL nativo. A sondagem Vulkan foi feita com probes C usando Vulkan-Headers v1.4.352; não havia `vulkaninfo` no aparelho. O número de API Vulkan observado para esse registro foi `1.4.352`; o renderer de GL identifica Mesa `26.1.6`, enquanto a identificação da sondagem Vulkan reporta `Mesa 26.2.0-devel`. Manter essas versões como saídas distintas das respectivas consultas, sem presumir que descrevem uma única build coerente.

Os resultados completos desta consulta (215 extensões GL, todos os limites GL, 22 extensões de instância, 168 extensões Vulkan e features Vulkan 1.0–1.4), métodos, falhas de sondagem e saídas brutas estão em [.specs/features/panvk-g86-evaluation/tasks/SKILL.md](.specs/features/panvk-g86-evaluation/tasks/SKILL.md). Os logs brutos citados ali incluem `/tmp/gl32forced.txt`, `/tmp/gl33core.txt`, `/tmp/gl33compat.txt`, `/tmp/gles31.txt`, `/tmp/vk_ext_full.txt`, `/tmp/vk_feat_full.txt` e `/tmp/vk_feat10_full.txt`; caminhos `/tmp` e `/opt` pertencem ao ambiente de consulta e não são artefatos versionados do repositório.

**Conclusão para o Poco X6 Pro / Mali-G615 MC6 medido:** NO-GO para OpenGL 4.x e GLES 3.2 neste PanVK/Zink observado; GL máximo observado 3.3 core/compat e GLES máximo 3.1. A falha de criação de contexto 4.x, junto das features Vulkan de geometria e tesselação ausentes nos defaults usados pelo PanVK não reconhecedor, sustenta o limite medido para essa execução. Não foi obtida uma matriz GL 4.x porque esses contextos não inicializaram. `MESA_GL_VERSION_OVERRIDE=4.6` ou overrides semelhantes só mudam a versão declarada; não habilitam geometry/tessellation nem provam conformidade ou funcionamento. Este resultado corrobora o NO-GO para GL 4.x observado no Moto G86 com a mesma arquitetura G615, sem substituir sua medição nem atribuir ao ICD ARM do G86 os limites específicos do fallback PanVK.

### Síntese comparativa — mesma Mali-G615, MC2 e MC6

| Aparelho / configuração | Caminho medido | Maior GL desktop reportado | Evidência sobre GL 4.x |
|---|---|---|---|
| Moto G86 / Mali-G615 MC2 (2 núcleos) | Zink sobre ICD ARM proprietário; Mesa 25.1.2 | 3.1 acelerado; 3.3 em softpipe (CPU) | Nenhum dos caminhos medidos reporta 4.x; o caminho acelerado não passa de 3.1 |
| Poco X6 Pro / Mali-G615 MC6 (6 núcleos) | Zink sobre PanVK não reconhecedor; Mesa 26.1.6 no renderer GL | 3.3 core/compat | Pedidos GL 4.0–4.6 falham ao criar contexto com `EGL_BAD_ALLOC` |

**Análise consolidada:** a conclusão prática é a mesma nos dois aparelhos que usam a mesma arquitetura Mali-G615: OpenGL desktop 4.x não está disponível/demonstrado nos caminhos medidos. MC2 versus MC6 representa 2 versus 6 núcleos de processamento, não uma diferença arquitetural que explique o nível de API. No Moto G86, a medição relevante para aceleração Mali reportou GL 3.1; GL 3.3 foi obtido apenas no renderer CPU softpipe. No Poco X6 Pro, o GL 3.3 veio de Zink/PanVK, mas a criação dos contexts 4.x falhou. Essa diferença no máximo GL observado acompanha os diferentes caminhos de driver/build e não prova que a contagem de núcleos altere o suporte a GL. No Poco, a ausência de `geometryShader` e `tessellationShader` explica o limite reportado pelo PanVK em fallback; isso é evidência da implementação PanVK consultada, não prova de ausência física dessas capacidades na arquitetura nem diagnóstico do ICD proprietário do G86. A base sustenta NO-GO para GL 4.x nos stacks testados, não uma impossibilidade universal para qualquer driver futuro da Mali-G615.

### Histórico de avaliações do candidato

`KNOWN_ISSUES.md`, seção “Mesa 26 on Android Mali” e subseções, mantém evidências/logs históricos da avaliação em cópia isolada. Esse histórico registra Mesa candidata 26.2.4 sem promoção, OpenGL 3.1 no caminho Zink e limitações/avisos relevantes. Não misturar resultados históricos com a medição atual: imagem, driver, estado do display e caminho de renderização precisam acompanhar qualquer comparação.

## Regras para evitar ambiguidade

- A versão Vulkan relevante é a `apiVersion` informada para o dispositivo/ICD real. Versão do loader ou da instância é um valor separado.
- Versão do pacote Mesa, artefato compilado ou marker de instalação não comprovam versão de API nem funcionamento.
- OpenGL desktop (GLX/Zink), OpenGL ES (EGL/GLES) e Vulkan são interfaces diferentes; resultado de uma não prova suporte às outras.
- `> 3.1` é estritamente maior que 3.1. O resultado 3.1 não passa. Para o alvo solicitado, é necessário reportar OpenGL desktop 4.6 no renderer alvo.
- Ferramenta, display ou log ausente significa **não verificado**, não **não suportado**.
- Não falsificar capabilities Vulkan nem forçar strings/profiles de versão OpenGL.

## Critérios de decisão futuros

| Avaliação | GO para avaliação adicional | NO-GO | INCONCLUSIVO |
|---|---|---|---|
| Vulkan 1.4 | `vulkaninfo` no aparelho reporta `apiVersion >= 1.4` para o Mali e inicialização funcional | ICD real continua abaixo de 1.4 ou depende de capability forjada | Sem enumeração do dispositivo/ICD ou teste interrompido |
| OpenGL desktop mínimo | `glxinfo -B` (ou equivalente no renderer alvo) reporta valor estritamente maior que 3.1 | Reporta 3.1 ou menor | Renderer, display ou versão não são identificados |
| OpenGL desktop 4.6 | Reporta 4.6 no caminho alvo e passa teste de desenho representativo; warnings/features registrados | Reporta abaixo de 4.6, feature necessária ausente ou desenho falha | Não foi possível inicializar renderer ou concluir teste |
| Promoção Mesa 26 | Resultados funcionais/estabilidade reproduzidos em cópia isolada, revisão humana e autorização explícita | Regressão, bloqueio ou requisito não atendido | Evidência parcial ou não reproduzível |

Vulkan e OpenGL são decisões separadas. Aprovação de uma API não aprova a outra nem promove Mesa automaticamente.

## Próximos passos planejados

1. Preservar Mesa 25.1.2 como baseline.
2. Se houver nova avaliação do Mesa candidato, fazê-la somente em imagem de teste separada via `device/setup/test-mesa-26.sh`; não instalar no rootfs de produção. O script cria/retém imagem e logs: verificar estado e espaço antes, não sobrescrever nem apagar artefatos existentes.
3. Registrar dispositivo, driver, imagem, hash do artefato, data, display, comandos, saídas completas e falhas.
4. Repetir medições equivalentes de Vulkan e GL no baseline e candidato; executar teste de desenho se aplicável. Comparar separadamente versão API real do ICD e versão GL realmente reportada.
5. Decidir GO/NO-GO/INCONCLUSIVO para cada interface. Não promover para produção sem evidência reproduzível, revisão humana e autorização explícita.

## Referências

- `docs/gpu.md` e `docs/gpu.pt.md`: operação do stack e wrappers.
- `KNOWN_ISSUES.md`: histórico e evidências de Mesa 25/26.
- `device/gpu/gpu-check.sh`: diagnóstico GLES-first e Vulkan opcional.
- `device/gpu/zink-run.sh`: wrapper do caminho GLX/Zink.
- `device/setup/test-mesa-26.sh`: avaliação isolada do candidato.
- `device/setup/install-mesa25-android-mali.sh`: versão do overlay Mesa 25.
